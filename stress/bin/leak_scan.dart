// Investigates whether HybridStreamEngine entries get cleaned up when a
// client of `GET /db/stream/list` goes away. Boots the same fixture
// `zonai serve` the rest of the stress harness uses, opens repeated waves of
// long-lived stream connections, drops each wave either gracefully or
// abruptly, and samples the server process's RSS/CPU throughout so growth
// (or its absence) is visible directly, not just theorized.
//
// Usage (from the stress/ directory):
//   dart run bin/leak_scan.dart --drop=graceful
//   dart run bin/leak_scan.dart --drop=abrupt --duration=5 --skip-build
//
// See stress/README.md's Findings section for how to interpret a run.
import 'dart:async';
import 'dart:io';

import 'package:zonai_stress/src/harness_setup.dart';
import 'package:zonai_stress/src/process_metrics.dart';
import 'package:zonai_stress/src/scenarios.dart' show waitForHealth;
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

    final stopSampling = Completer<void>();
    final samples = <ProcessSample>[];
    final samplingDone = sampleProcess(
      server.pid,
      interval: Duration(seconds: args.sampleIntervalSeconds),
      stop: stopSampling.future,
    ).forEach(samples.add);

    print(
      'Running stream waves for ${args.durationMinutes}min '
      '(${args.streamsPerWave} streams/wave, hold '
      '${args.holdSeconds}s, every ${args.waveIntervalSeconds}s, '
      'drop=${args.drop.name})...',
    );
    final waveStats = await runStreamWaves(
      baseUri: baseUri,
      totalDuration: Duration(
        milliseconds: (args.durationMinutes * 60 * 1000).round(),
      ),
      holdDuration: Duration(seconds: args.holdSeconds),
      waveInterval: Duration(seconds: args.waveIntervalSeconds),
      streamsPerWave: args.streamsPerWave,
      dropMode: args.drop,
    );

    stopSampling.complete();
    await samplingDone;

    print('');
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
    );
  }
}
