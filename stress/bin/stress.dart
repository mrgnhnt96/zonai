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
import 'dart:convert';
import 'dart:io';

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

  await _ensureCompiledZonai(zonaiExe, zonaiPackageDir, force: args.recompile);
  await _ensureFixtureReady(
    fixtureDir: fixtureDir,
    zonaiExe: zonaiExe,
    skipBuild: args.skipBuild,
  );

  print('Starting server on port ${args.port}...');
  final server = await Process.start('${buildDir.path}/zonai', [
    'serve',
    '--port',
    '${args.port}',
    '--no-version-check',
    '--no-open',
  ], workingDirectory: buildDir.path);
  final logSink = serverLog.openWrite();
  server.stdout.transform(const SystemEncoding().decoder).listen(logSink.write);
  server.stderr.transform(const SystemEncoding().decoder).listen(logSink.write);

  try {
    final healthy = await waitForHealth(baseUri);
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

Future<void> _ensureCompiledZonai(
  File zonaiExe,
  Directory zonaiPackageDir, {
  required bool force,
}) async {
  if (!force && zonaiExe.existsSync()) {
    print('Using cached compiled zonai at ${zonaiExe.path}');
    return;
  }
  print('Compiling zonai CLI (this happens once, ~30s)...');
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '-D__ZONAI_COMPILED__=true',
    'bin/zonai.dart',
    '-o',
    zonaiExe.path,
  ], workingDirectory: zonaiPackageDir.path);
  if (result.exitCode != 0) {
    throw StateError(
      'dart compile exe failed:\n${result.stderr}\n${result.stdout}',
    );
  }
}

Future<void> _ensureFixtureReady({
  required Directory fixtureDir,
  required File zonaiExe,
  required bool skipBuild,
}) async {
  final packageConfig = File(
    '${fixtureDir.path}/.dart_tool/package_config.json',
  );
  if (!packageConfig.existsSync()) {
    print('Fetching fixture dependencies (dart pub get)...');
    await _run(Platform.resolvedExecutable, ['pub', 'get'], fixtureDir.path);
  }

  final migrationsDir = Directory('${fixtureDir.path}/.zonai/migrations');
  if (!migrationsDir.existsSync() || migrationsDir.listSync().isEmpty) {
    print('Generating and applying initial migration...');
    await _run(zonaiExe.path, [
      'db',
      'migrate',
      'generate',
      '--name',
      'initialize',
      '--no-version-check',
    ], fixtureDir.path);
    await _run(zonaiExe.path, [
      'db',
      'migrate',
      'apply',
      '--no-version-check',
    ], fixtureDir.path);
  }

  final buildDir = Directory('${fixtureDir.path}/build');
  if (skipBuild && buildDir.existsSync()) {
    print('--skip-build set; reusing existing build/.');
    return;
  }

  print('Building fixture (zonai build)...');
  await _run(zonaiExe.path, ['build', '--no-version-check'], fixtureDir.path);
}

Future<void> _run(String executable, List<String> args, String cwd) async {
  final result = await Process.run(executable, args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${args.join(' ')} failed in $cwd:\n'
      '${result.stderr}\n${result.stdout}',
    );
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
    required this.jsonOutput,
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
  final String? jsonOutput;

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

    return _Args(
      port: int.parse(map['port'] ?? '8099'),
      concurrency: parseIntList(map['concurrency'], [1, 10, 25, 50, 100]),
      durationSeconds: int.parse(map['duration'] ?? '5'),
      warmupSeconds: int.parse(map['warmup'] ?? '1'),
      scenarios:
          (map['scenarios'] ?? 'list,create,mixed,auth-signin,auth-signup')
              .split(',')
              .toSet(),
      seedRows: int.parse(map['seed'] ?? '200'),
      skipBuild: flags.contains('skip-build'),
      recompile: flags.contains('recompile'),
      keepServer: flags.contains('keep-server'),
      jsonOutput: map['json'],
    );
  }
}
