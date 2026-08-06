// Investigates whether the compiled zonai binary's RSS grows unboundedly
// under sustained, varied traffic -- mixed CRUD (list/create/delete) at
// realistic concurrency, plus stream connections mixing list/one/count with
// varied parameters (so HybridStreamEngine accumulates many distinct
// entries, not just one repeatedly-cached one) -- dropped either gracefully
// or abruptly. Boots the same fixture `zonai serve` the rest of the stress
// harness uses and samples the server process's RSS/CPU throughout so
// growth (or its absence) is visible directly, not just theorized.
//
// Usage (from the stress/ directory):
//   dart run bin/leak_scan.dart --drop=graceful
//   dart run bin/leak_scan.dart --drop=abrupt --duration=15
//
// Do NOT pass --skip-build if a dependency (e.g. a local revali checkout)
// changed since the last run -- the fixture's project-linked binary is an
// AOT snapshot and only picks up source changes on a fresh `zonai build`.
//
// See stress/README.md's Findings section for how to interpret a run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:zonai_stress/src/harness_setup.dart';
import 'package:zonai_stress/src/load_runner.dart';
import 'package:zonai_stress/src/process_metrics.dart';
import 'package:zonai_stress/src/scenarios.dart';
import 'package:zonai_stress/src/stats.dart';
import 'package:zonai_stress/src/stream_scenarios.dart';

Future<void> main(List<String> rawArgs) async {
  final args = _Args.parse(rawArgs);

  final stressDir = Directory(
    File(Platform.script.toFilePath()).parent.parent.path,
  );
  final repoRoot = Directory(stressDir.parent.path);
  final fixtureDir = Directory('${stressDir.path}/fixture');
  final zonaiPackageDir = Directory('${repoRoot.path}/apps/zonai');
  final cacheDir = Directory('${stressDir.path}/.cache')..createSync();
  final zonaiExe = File('${cacheDir.path}/zonai_exe');
  final buildDir = Directory('${fixtureDir.path}/build');
  final serverLog = File('${cacheDir.path}/leak_scan_server.log');
  final resultsDir = Directory('${stressDir.path}/results')..createSync();

  final baseUri = Uri.parse('http://localhost:${args.port}');

  print('== zonai leak scan (drop=${args.drop.name}, mode=${args.mode.name}) ==');

  await ensureCompiledZonai(
    zonaiExe,
    zonaiPackageDir,
    force: args.recompile,
    repoRoot: repoRoot,
  );
  await ensureFixtureReady(
    fixtureDir: fixtureDir,
    repoRoot: repoRoot,
    zonaiExe: zonaiExe,
    skipBuild: args.skipBuild,
    mode: args.mode,
  );

  print('Starting server on port ${args.port} (mode=${args.mode.name})...');
  if (args.resetDb) {
    resetFixtureDb(fixtureDir: fixtureDir, buildDir: buildDir, mode: args.mode);
  }
  final server = await startServer(
    mode: args.mode,
    port: args.port,
    fixtureDir: fixtureDir,
    buildDir: buildDir,
  );
  final logSink = serverLog.openWrite();
  final logSubs = <StreamSubscription<String>>[
    server.stdout.transform(const SystemEncoding().decoder).listen(logSink.write),
    server.stderr.transform(const SystemEncoding().decoder).listen(logSink.write),
  ];

  try {
    final healthy = await waitForHealth(
      baseUri,
      timeout: args.mode == ServerMode.dev
          ? const Duration(seconds: 90)
          : const Duration(seconds: 30),
    );
    if (!healthy) {
      stderr.writeln('Server did not become healthy in time. See ${serverLog.path}');
      exitCode = 1;
      return;
    }
    print('Server healthy (pid ${server.pid}).');

    print('Seeding ${args.seedRows} rows for stream one/count variety...');
    final knownIds = await _seedAndCollectIds(baseUri, count: args.seedRows);
    print('Seeded ${knownIds.length} rows.');

    final stopSampling = Completer<void>();
    final samples = <ProcessSample>[];
    final samplingDone = sampleProcess(
      server.pid,
      interval: Duration(seconds: args.sampleIntervalSeconds),
      stop: stopSampling.future,
    ).forEach(samples.add);

    final totalDuration = Duration(
      milliseconds: (args.durationMinutes * 60 * 1000).round(),
    );

    print(
      'Running ${args.durationMinutes}min of mixed traffic: CRUD '
      '(list@${args.crudConcurrency}, create@${args.crudConcurrency ~/ 2}, '
      'delete@${args.crudConcurrency ~/ 2}) concurrently with stream waves '
      '(${args.streamsPerWave} streams/wave mixing list/one/count, hold '
      '${args.holdSeconds}s, every ${args.waveIntervalSeconds}s, '
      'drop=${args.drop.name})...',
    );
    final runner = LoadRunner();
    final results = await Future.wait([
      runner.run(
        scenario: 'list',
        sender: listItems(baseUri),
        concurrency: args.crudConcurrency,
        duration: totalDuration,
        warmup: Duration.zero,
      ),
      runner.run(
        scenario: 'create',
        sender: createItem(baseUri),
        concurrency: max(1, args.crudConcurrency ~/ 2),
        duration: totalDuration,
        warmup: Duration.zero,
      ),
      runner.run(
        scenario: 'delete',
        sender: deleteItem(baseUri),
        concurrency: max(1, args.crudConcurrency ~/ 2),
        duration: totalDuration,
        warmup: Duration.zero,
      ),
      runStreamWaves(
        baseUri: baseUri,
        totalDuration: totalDuration,
        holdDuration: Duration(seconds: args.holdSeconds),
        waveInterval: Duration(seconds: args.waveIntervalSeconds),
        streamsPerWave: args.streamsPerWave,
        dropMode: args.drop,
        knownIds: knownIds,
      ),
    ]);

    stopSampling.complete();
    await samplingDone;

    final crudStats = results.take(3).cast<ScenarioStats>().toList();
    final waveStats = results[3] as StreamWaveStats;

    print('');
    for (final s in crudStats) {
      print(
        '${s.scenario}: ${s.requestsPerSecond.toStringAsFixed(1)} req/s, '
        'p95=${s.p95.toStringAsFixed(1)}ms, errors=${s.errors}/${s.total}',
      );
    }
    print('Wave stats: $waveStats');
    final summary = LeakSummary.fromSamples(samples);
    print('RSS summary: $summary');

    final csv = StringBuffer('${ProcessSample.csvHeader}\n');
    for (final s in samples) {
      csv.writeln(s.toCsvRow());
    }
    final outFile = File(
      '${resultsDir.path}/leak_scan_${args.mode.name}_${args.drop.name}.csv',
    );
    outFile.writeAsStringSync(csv.toString());
    print('Wrote ${samples.length} samples to ${outFile.path}');
  } finally {
    if (!args.keepServer) {
      print('Stopping server...');
      server.kill(ProcessSignal.sigterm);
      final exited = await server.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          server.kill(ProcessSignal.sigkill);
          return server.exitCode;
        },
      );
      for (final sub in logSubs) {
        await sub.cancel();
      }
      await logSink.close();
      print('Server stopped (exit $exited). Log at ${serverLog.path}');
    } else {
      print('--keep-server set; server still running at $baseUri (pid ${server.pid}).');
    }
  }
}

/// Creates [count] rows via `POST /db` and returns their ids, so
/// `/db/stream` (one) and `/db/stream/count` have real rows to query --
/// `_streamOne` throws before ever reaching HybridStreamEngine if its
/// `where` matches nothing.
Future<List<String>> _seedAndCollectIds(Uri baseUri, {required int count}) async {
  final client = HttpClient();
  final ids = <String>[];
  try {
    final uri = baseUri.replace(path: '/db');
    for (var i = 0; i < count; i++) {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'table': 'items',
          'object': {'name': 'leak-scan-seed-$i'},
        }),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) continue;
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['data'] is Map) {
        final id = (decoded['data'] as Map)['id'];
        if (id is String && id.isNotEmpty) ids.add(id);
      }
    }
  } finally {
    client.close(force: true);
  }
  return ids;
}

class _Args {
  _Args({
    required this.port,
    required this.durationMinutes,
    required this.holdSeconds,
    required this.waveIntervalSeconds,
    required this.streamsPerWave,
    required this.sampleIntervalSeconds,
    required this.drop,
    required this.mode,
    required this.skipBuild,
    required this.recompile,
    required this.keepServer,
    required this.resetDb,
    required this.crudConcurrency,
    required this.seedRows,
  });

  final int port;
  final double durationMinutes;
  final int holdSeconds;
  final int waveIntervalSeconds;
  final int streamsPerWave;
  final int sampleIntervalSeconds;
  final DropMode drop;
  final ServerMode mode;
  final bool skipBuild;
  final bool recompile;
  final bool keepServer;
  final bool resetDb;
  final int crudConcurrency;
  final int seedRows;

  static _Args parse(List<String> raw) {
    final map = <String, String>{};
    final flags = <String>{};
    for (final arg in raw) {
      if (!arg.startsWith('--')) continue;
      final bodyArg = arg.substring(2);
      final eq = bodyArg.indexOf('=');
      if (eq == -1) {
        flags.add(bodyArg);
      } else {
        map[bodyArg.substring(0, eq)] = bodyArg.substring(eq + 1);
      }
    }

    final modeName = map['mode'] ?? 'dev';
    final mode = switch (modeName) {
      'dev' || 'jit' => ServerMode.dev,
      'build' || 'release' => ServerMode.build,
      _ => throw FormatException('Unknown --mode=$modeName (expected dev|build)'),
    };

    final dropName = map['drop'] ?? 'abrupt';
    final drop = switch (dropName) {
      'graceful' || 'clean' => DropMode.graceful,
      'abrupt' || 'force' => DropMode.abrupt,
      _ => throw FormatException(
        'Unknown --drop=$dropName (expected graceful|abrupt)',
      ),
    };

    return _Args(
      port: int.parse(map['port'] ?? '8098'),
      durationMinutes: double.parse(map['duration'] ?? '3'),
      holdSeconds: int.parse(map['hold'] ?? '2'),
      waveIntervalSeconds: int.parse(map['wave-interval'] ?? '3'),
      streamsPerWave: int.parse(map['streams-per-wave'] ?? '20'),
      sampleIntervalSeconds: int.parse(map['sample-interval'] ?? '1'),
      drop: drop,
      mode: mode,
      skipBuild: flags.contains('skip-build'),
      recompile: flags.contains('recompile'),
      keepServer: flags.contains('keep-server'),
      resetDb: !flags.contains('keep-db'),
      crudConcurrency: int.parse(map['crud-concurrency'] ?? '10'),
      seedRows: int.parse(map['seed'] ?? '50'),
    );
  }
}
