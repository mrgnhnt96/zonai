// Load-testing harness for zonai.
//
// Builds the fixture app under stress/fixture, boots a compiled zonai
// server from it, drives concurrent HTTP load against it at a sweep of
// concurrency levels, and prints a throughput/latency report.
//
// Usage (from the stress/ directory):
//   dart run bin/stress.dart
//   dart run bin/stress.dart --concurrency=1,10,50,100 --duration=5
//   dart run bin/stress.dart --scenarios=list,create --skip-build
//
// See stress/README.md for flag documentation and interpretation notes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zonai_stress/src/harness_setup.dart';
import 'package:zonai_stress/src/load_runner.dart';
import 'package:zonai_stress/src/report.dart';
import 'package:zonai_stress/src/scenarios.dart';
import 'package:zonai_stress/src/stats.dart';

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
  final serverLog = File('${cacheDir.path}/server.log');

  final baseUri = Uri.parse('http://localhost:${args.port}');

  print('== zonai stress harness ==');

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
    server.stdout
        .transform(const SystemEncoding().decoder)
        .listen(logSink.write),
    server.stderr
        .transform(const SystemEncoding().decoder)
        .listen(logSink.write),
  ];

  try {
    final healthy = await waitForHealth(
      baseUri,
      timeout: args.mode == ServerMode.dev
          ? const Duration(seconds: 90)
          : const Duration(seconds: 30),
    );
    if (!healthy) {
      stderr.writeln(
        'Server did not become healthy in time. See ${serverLog.path}',
      );
      exitCode = 1;
      return;
    }
    print('Server healthy.');

    await _seed(baseUri, count: args.seedRows);

    final allStats = <ScenarioStats>[];
    final runner = LoadRunner();
    final scenarios = _buildScenarios(baseUri, args.scenarios);

    for (final scenario in scenarios) {
      for (final concurrency in args.concurrency) {
        stdout.write(
          '  ${scenario.name} @ concurrency=$concurrency '
          '(${args.durationSeconds}s)... ',
        );
        final stats = await runner.run(
          scenario: scenario.name,
          sender: scenario.sender,
          concurrency: concurrency,
          duration: Duration(seconds: args.durationSeconds),
          warmup: Duration(seconds: args.warmupSeconds),
        );
        allStats.add(stats);
        print(
          '${stats.requestsPerSecond.toStringAsFixed(1)} req/s, '
          'p95=${stats.p95.toStringAsFixed(1)}ms, '
          'errors=${stats.errors}/${stats.total}',
        );
      }
    }

    print(renderReport(allStats));

    if (args.jsonOutput != null) {
      final file = File(args.jsonOutput!);
      // `results/` is gitignored, so it does not exist in a fresh checkout --
      // create it (and any nested path) before writing the sweep results.
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(allStats.map((s) => s.toJson()).toList()),
      );
      print('Wrote JSON results to ${file.path}');
    }
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
      print(
        '--keep-server set; server still running at $baseUri (pid ${server.pid}).',
      );
    }
  }
}

class _NamedScenario {
  const _NamedScenario(this.name, this.sender);
  final String name;
  final RequestSender sender;
}

List<_NamedScenario> _buildScenarios(Uri baseUri, Set<String> names) {
  const testEmail = 'stress-fixed-user@example.com';
  const testPassword = 'hunter22';

  final all = <String, RequestSender>{
    'list': listItems(baseUri),
    'create': createItem(baseUri),
    'delete': deleteItem(baseUri),
    'mixed': mixedReadWrite(baseUri),
    'auth-signup': signUp(baseUri),
    'auth-signin': signIn(baseUri, email: testEmail, password: testPassword),
  };

  return [
    for (final name in names)
      if (all[name] case final sender?) _NamedScenario(name, sender),
  ];
}

Future<void> _seed(Uri baseUri, {required int count}) async {
  print('Seeding $count rows and one auth user...');
  final client = HttpClient();
  try {
    final create = createItem(baseUri);
    for (var i = 0; i < count; i++) {
      await create(client);
    }
    // Inlined (rather than reusing signUp()) so the seeded account has a
    // fixed, known email the auth-signin scenario can log in with.
    final request = await client.postUrl(
      baseUri.replace(path: '/auth/sign-up'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'type': 'signUp',
        'table': 'users',
        'email': 'stress-fixed-user@example.com',
        'password': 'hunter22',
      }),
    );
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode >= 300) {
      stderr.writeln(
        'Warning: seeding fixed auth user failed (HTTP ${response.statusCode}); '
        'auth-signin scenario will error out.',
      );
    }
  } finally {
    client.close(force: true);
  }
}

class _Args {
  _Args({
    required this.port,
    required this.concurrency,
    required this.durationSeconds,
    required this.warmupSeconds,
    required this.scenarios,
    required this.seedRows,
    required this.skipBuild,
    required this.recompile,
    required this.keepServer,
    required this.resetDb,
    required this.jsonOutput,
    required this.mode,
  });

  final int port;
  final List<int> concurrency;
  final int durationSeconds;
  final int warmupSeconds;
  final Set<String> scenarios;
  final int seedRows;
  final bool skipBuild;
  final bool recompile;
  final bool keepServer;
  final bool resetDb;
  final String? jsonOutput;
  final ServerMode mode;

  static _Args parse(List<String> raw) {
    final map = <String, String>{};
    final flags = <String>{};
    for (final arg in raw) {
      if (!arg.startsWith('--')) continue;
      final body = arg.substring(2);
      final eq = body.indexOf('=');
      if (eq == -1) {
        flags.add(body);
      } else {
        map[body.substring(0, eq)] = body.substring(eq + 1);
      }
    }

    List<int> parseIntList(String? v, List<int> fallback) =>
        v == null ? fallback : v.split(',').map(int.parse).toList();

    final modeName = map['mode'] ?? 'build';
    final mode = switch (modeName) {
      'dev' || 'jit' => ServerMode.dev,
      'build' || 'release' => ServerMode.build,
      _ => throw FormatException(
        'Unknown --mode=$modeName (expected dev|build)',
      ),
    };

    return _Args(
      port: int.parse(map['port'] ?? '8099'),
      concurrency: parseIntList(map['concurrency'], [1, 10, 25, 50, 100]),
      durationSeconds: int.parse(map['duration'] ?? '5'),
      warmupSeconds: int.parse(map['warmup'] ?? '1'),
      scenarios:
          (map['scenarios'] ??
                  'list,create,delete,mixed,auth-signin,auth-signup')
              .split(',')
              .toSet(),
      seedRows: int.parse(map['seed'] ?? '200'),
      skipBuild: flags.contains('skip-build'),
      recompile: flags.contains('recompile'),
      keepServer: flags.contains('keep-server'),
      // Default: wipe SQLite so sweeps are comparable. --keep-db preserves it.
      resetDb: !flags.contains('keep-db'),
      jsonOutput: map['json'],
      mode: mode,
    );
  }
}
