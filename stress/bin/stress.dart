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

  await _ensureCompiledZonai(
    zonaiExe,
    zonaiPackageDir,
    force: args.recompile,
    repoRoot: repoRoot,
  );
  await _ensureFixtureReady(
    fixtureDir: fixtureDir,
    repoRoot: repoRoot,
    zonaiExe: zonaiExe,
    skipBuild: args.skipBuild,
    mode: args.mode,
  );

  print('Starting server on port ${args.port} (mode=${args.mode.name})...');
  if (args.resetDb) {
    _resetFixtureDb(fixtureDir: fixtureDir, buildDir: buildDir, mode: args.mode);
  }
  final server = await _startServer(
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
      timeout: args.mode == _ServerMode.dev
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

/// Deletes fixture SQLite files so each harness run starts from an empty DB
/// (auto-migrate on serve recreates schema). Pass `--keep-db` to skip.
void _resetFixtureDb({
  required Directory fixtureDir,
  required Directory buildDir,
  required _ServerMode mode,
}) {
  final roots = <Directory>[
    Directory('${fixtureDir.path}/.zonai/data'),
    if (mode == _ServerMode.build)
      Directory('${buildDir.path}/.zonai/data'),
  ];
  var deleted = 0;
  for (final dir in roots) {
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('zonai.sqlite')) continue;
      entity.deleteSync();
      deleted++;
    }
  }
  if (deleted > 0) {
    print('Reset DB: removed $deleted sqlite file(s) before serve.');
  } else {
    print('Reset DB: no existing sqlite files.');
  }
}

Future<Process> _startServer({
  required _ServerMode mode,
  required int port,
  required Directory fixtureDir,
  required Directory buildDir,
}) async {
  final serveArgs = [
    'serve',
    '--port',
    '$port',
    '--no-version-check',
    '--no-open',
  ];

  return switch (mode) {
    // Dev workflow: `dart run zonai serve` → JIT project_main (ops/rules
    // in-process, no AOT project binary). Matches day-to-day `zonai serve`
    // / the server `zonai dev` attaches to when not using a compiled CLI.
    _ServerMode.dev => Process.start(
      Platform.resolvedExecutable,
      ['run', 'zonai', ...serveArgs],
      workingDirectory: fixtureDir.path,
    ),
    // Production artifact: project-linked `build/zonai serve --release`.
    _ServerMode.build => Process.start(
      '${buildDir.path}/zonai',
      [...serveArgs, '--release'],
      workingDirectory: buildDir.path,
    ),
  };
}

Future<void> _ensureCompiledZonai(
  File zonaiExe,
  Directory zonaiPackageDir, {
  required bool force,
  required Directory repoRoot,
}) async {
  final versionFile = File('${repoRoot.path}/VERSION');
  final expectedVersion = versionFile.existsSync()
      ? versionFile.readAsStringSync().trim()
      : null;

  if (!force && zonaiExe.existsSync()) {
    final reported = await _extractZonaiVersion(zonaiExe);
    if (expectedVersion == null || reported == expectedVersion) {
      print('Using cached compiled zonai at ${zonaiExe.path} (v$reported)');
      return;
    }
    print(
      'Cached zonai is v$reported but VERSION is $expectedVersion; '
      'recompiling...',
    );
  } else if (force) {
    print('Recompiling zonai CLI (--recompile)...');
  } else {
    print('Compiling zonai CLI (this happens once, ~30s)...');
  }

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
  final reported = await _extractZonaiVersion(zonaiExe);
  print('Compiled zonai CLI v$reported → ${zonaiExe.path}');
}

Future<String?> _extractZonaiVersion(File zonaiExe) async {
  final result = await Process.run(zonaiExe.path, ['version'], environment: {
    // Avoid "new version available" noise affecting parsing.
    'CI': '1',
  });
  final match = RegExp(
    r'Zonai: v([0-9][0-9.]*)',
  ).firstMatch('${result.stdout}\n${result.stderr}');
  return match?.group(1);
}

Future<void> _ensureFixtureReady({
  required Directory fixtureDir,
  required Directory repoRoot,
  required File zonaiExe,
  required bool skipBuild,
  required _ServerMode mode,
}) async {
  _ensureFixturePubOverrides(fixtureDir, repoRoot);

  print('Fetching fixture dependencies (dart pub get)...');
  await _run(Platform.resolvedExecutable, ['pub', 'get'], fixtureDir.path);

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

  final executablesDir = Directory('${fixtureDir.path}/.zonai/executables');
  if (!skipBuild || !executablesDir.existsSync()) {
    print('Compiling fixture workers (zonai compile)...');
    await _run(zonaiExe.path, [
      'compile',
      '--no-version-check',
    ], fixtureDir.path);
  }

  if (mode == _ServerMode.dev) {
    print('Dev mode: skipping zonai build (using JIT project entry).');
    return;
  }

  final buildDir = Directory('${fixtureDir.path}/build');
  final built = File('${buildDir.path}/zonai');
  if (skipBuild && built.existsSync()) {
    print('--skip-build set; reusing existing ${built.path}');
    return;
  }

  print('Building fixture (zonai build)...');
  await _run(zonaiExe.path, ['build', '--no-version-check'], fixtureDir.path);

  if (!built.existsSync()) {
    throw StateError('zonai build did not produce ${built.path}');
  }

  // Guard against a stale bootstrap CLI that still *copies* itself into
  // build/zonai instead of compiling a project-linked binary.
  if (_sameFileBytes(built, zonaiExe)) {
    throw StateError(
      'fixture/build/zonai is identical to the bootstrap CLI cache — '
      'zonai build did not produce a project-linked binary. '
      'Recompile the cache with --recompile (needs a zonai that has '
      'ProjectBinary.compile).',
    );
  }

  print(
    'Built project binary at ${built.path} (${built.lengthSync()} bytes).',
  );
}

/// Writes gitignored [pubspec_overrides.yaml] so project-binary compile can
/// resolve local resqlite + revali the same way the monorepo workspace does.
void _ensureFixturePubOverrides(Directory fixtureDir, Directory repoRoot) {
  final revaliRoot = _resolveRevaliRoot(repoRoot);
  final overrides = File('${fixtureDir.path}/pubspec_overrides.yaml');
  overrides.writeAsStringSync('''
# Generated by stress/bin/stress.dart — do not commit (gitignored).
dependency_overrides:
  resqlite:
    path: ${repoRoot.path}/libs/resqlite
  revali_swagger:
    path: ${revaliRoot.path}/constructs/revali_swagger/revali_swagger
  revali_swagger_annotations:
    path: ${revaliRoot.path}/constructs/revali_swagger/revali_swagger_annotations
  revali_router:
    path: ${revaliRoot.path}/revali_router/revali_router
  revali:
    path: ${revaliRoot.path}/packages/revali
  revali_client:
    path: ${revaliRoot.path}/constructs/revali_client/revali_client
  revali_client_gen:
    path: ${revaliRoot.path}/constructs/revali_client/revali_client_gen
  revali_construct:
    path: ${revaliRoot.path}/packages/revali_construct
  revali_core:
    path: ${revaliRoot.path}/packages/revali_core
  revali_annotations:
    path: ${revaliRoot.path}/packages/revali_annotations
''');
}

Directory _resolveRevaliRoot(Directory repoRoot) {
  // Monorepo pubspec_overrides use `../../revali` from zonai → Development/revali.
  final candidates = [
    Directory('${repoRoot.parent.parent.path}/revali'),
    Directory('${repoRoot.parent.path}/revali'),
    Directory('${repoRoot.path}/../revali'),
  ];
  for (final dir in candidates) {
    if (Directory('${dir.path}/packages/revali').existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError(
    'Could not find local revali checkout. Tried:\n'
    '${candidates.map((d) => '  - ${d.path}').join('\n')}',
  );
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

bool _sameFileBytes(File a, File b) {
  if (!a.existsSync() || !b.existsSync()) return false;
  if (a.lengthSync() != b.lengthSync()) return false;
  // Detect the pre-ProjectBinary `zonai build` failure mode that copies the
  // bootstrap CLI into build/zonai verbatim.
  return a.readAsBytesSync() == b.readAsBytesSync();
}

enum _ServerMode {
  /// JIT project entry via `dart run zonai serve` (dev workflow).
  dev,

  /// Project-linked AOT from `zonai build` (`build/zonai serve --release`).
  build,
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
  final _ServerMode mode;

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
      'dev' || 'jit' => _ServerMode.dev,
      'build' || 'release' => _ServerMode.build,
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
