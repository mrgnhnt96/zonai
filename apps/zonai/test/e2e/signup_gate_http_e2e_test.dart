import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../lib/gen/server/.revali/server/server.dart' as gen_server;
import '../support/temp_directory.dart';

/// HTTP-layer proof, over a REAL socket against the actual generated server
/// (`apps/zonai/lib/gen/server`, the same code `zonai compile`/`zonai serve`
/// embeds), that a sign-up declined by `AuthExtension.beforeSignUp` is
/// answered **403 with the reason**, not 500.
///
/// This is the half `signup_gate_e2e_test.dart` cannot reach. That file drives
/// `ZonaiDb` directly through the real `db_extensions.exe` worker, so it proves
/// the hook runs, that the refusal propagates, and that no row/session/verify-
/// email survives it -- but it never renders a response, so the STATUS CODE is
/// outside what it can see.
///
/// The status is not a formality here, and the gap is not theoretical. Revali
/// generates one `if (exception is T)` arm per `@ExceptionCatcher` method into
/// `.revali/.../exceptions_exception_catcher.dart`. Until that is regenerated,
/// `onSignUpDeclined` is not registered at all and a declined sign-up falls
/// through to the generic handler as a **500**. The merge that landed the gate
/// (`ddc5a1ee`) left exactly that state: the vendored mirror carried zero
/// occurrences of `onSignUpDeclined`, while every test in the suite was green.
///
/// `apps/zonai/tool/server_mirror_check.dart` cannot close it either -- it
/// excludes `.revali/` on purpose (its own header explains why: including
/// regenerated output would make the gate flap, and a flapping gate gets
/// disabled). It reports `matches apps/server` with the catcher arm missing.
/// So this file is the backstop that comment defers to, made real: it imports
/// the mirror and drives it, which is the only way the arm's absence becomes a
/// failing test rather than a silent 500 in production.
///
/// Both outcomes run against the SAME live server in one pass. A file that
/// only proved the refusal could not tell a working gate apart from a blanket
/// 403 -- see `e2e/signup_gate_repro`'s own doc comment, which splits by email
/// domain for that reason rather than by a flag the test flips.
///
/// See `admin_invite_http_oauth_e2e_test.dart`'s doc comment for why
/// `gen_server.createServer` is called in-process rather than shelling out to
/// `zonai serve`, and why this lives in its own file/isolate:
/// `zonaiDbProvider`/`operationsProvider` et al. cache a module-level singleton
/// across `runMergedScopedFuture` calls within one isolate, so a second fixture
/// in the same file would silently reuse the first one's.
void main() {
  group('signup gate HTTP e2e (e2e/signup_gate_repro)', () {
    late Directory projectRoot;
    late _LiveServer server;
    late http.Client client;
    final unique = DateTime.now().microsecondsSinceEpoch;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = _resolveFixture('signup_gate_repro');
      projectRoot = createCanonicalTempSync('zonai_signup_gate_http_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(
        projectRoot: projectRoot,
        repoRoot: repoRoot,
        packageName: 'zonai_signup_gate_repro',
      );

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
      ], workingDirectory: projectRoot.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}\n${pubGet.stdout}');

      final settings = await runMergedScopedFuture(
        () async => Settings.load(projectRoot.path),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );

      await runMergedScopedFuture(() async {
        await _runZonai(projectRoot, [
          'compile',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await _runZonai(projectRoot, [
          'db',
          'migrate',
          'generate',
          '--name',
          'initialize',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await _runZonai(projectRoot, [
          'db',
          'migrate',
          'apply',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
      }, override: _e2eScopeOverrides(settings));

      server = await _LiveServer.start(settings);
      client = http.Client();
    });

    tearDownAll(() async {
      if (!_runningOnDartVm) return;
      client.close();
      await server.close();
      deleteTempDirectory(projectRoot);
    });

    test('a declined sign-up is answered 403 with the hook\'s reason, while an '
        'allowed one on the same server still succeeds', () async {
      if (!_runningOnDartVm) return;

      final declined = await client.post(
        server.uri('/auth/sign-up'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'table': 'users',
          'type': 'signUp',
          'email': 'blocked-$unique$_declinedDomain',
          'password': 'declined-pw-1',
        }),
      );

      // The whole point: 403, not the 500 an unregistered catcher arm gives.
      expect(declined.statusCode, 403, reason: declined.body);

      // The reason survives the wire. It crosses a process boundary as text
      // (`SignUpDeclinedException.toString`/`tryParse` are two halves of one
      // protocol) before it ever reaches the catcher, so asserting the status
      // alone would not prove the author's message came back at all.
      expect(declined.body, contains(_declinedReason));

      // ...and no session was issued alongside it.
      expect(declined.body, isNot(contains('accessToken')));

      // Not a blanket 403: the same live server, same compiled worker, same
      // table -- only the address differs.
      final allowed = await client.post(
        server.uri('/auth/sign-up'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'table': 'users',
          'type': 'signUp',
          'email': 'allowed-$unique@example.com',
          'password': 'allowed-pw-1',
        }),
      );

      expect(allowed.statusCode, 200, reason: allowed.body);
      expect(_asMap(allowed)['accessToken'], isA<String>());
    });
  });
}

/// Mirrors `UsersExtensions.declinedDomain`/`.reason` in
/// `e2e/signup_gate_repro/lib/src/extensions/users_extensions.dart`.
///
/// Duplicated rather than imported: the fixture is a separate package that this
/// test package does not depend on, and it is driven here over HTTP as a black
/// box, exactly as a real client would.
const _declinedDomain = '@blocked.test';
const _declinedReason = 'Sign-up from that domain is not accepted';

// ===========================================================================
// Shared HTTP helpers.
// ===========================================================================

/// Revali's default response handler wraps a returned `Map` body in a
/// `{"data": ...}` envelope; this unwraps it so callers can read the
/// handler's own return shape (`{accessToken, user}`) directly.
Map<String, dynamic> _asMap(http.Response response) {
  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  return switch (decoded) {
    {'data': final Map<String, dynamic> data} => data,
    _ => decoded,
  };
}

// ===========================================================================
// A real, live server, bound in-process (see admin_invite_http_oauth_e2e_
// test.dart's doc comment for why).
// ===========================================================================

class _LiveServer {
  _LiveServer._(this._httpServer);

  final HttpServer _httpServer;

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.http('127.0.0.1:${_httpServer.port}', path, query);

  static Future<_LiveServer> start(Settings settings) async {
    final httpServer = await runMergedScopedFuture(
      () => gen_server.createServer(null, const []),
      override: {
        argsProvider.overrideWith(
          () => Args.parse(const ['--host=127.0.0.1', '--port=0']),
        ),
        fsProvider.overrideWith(LocalFileSystem.new),
        loggerProvider.overrideWith(() => Logger(level: .error)),
        settingsProvider.overrideWith(() => settings),
        // Everything else, at its production default -- mirrors
        // `apps/zonai/lib/src/bootstrap.dart`'s `runZonai` registration set.
        envProvider,
        courierProvider,
        processProvider,
        cleanUpProvider,
        mutationsProvider,
        keyboardInputProvider,
        messageContractHashProvider,
        migrateProvider,
        extensionsProvider,
        executableStopProvider,
        rulesProvider,
        rateLimitsProvider,
        cronsProvider,
        rateLimiterProvider,
        configProvider,
        configResolverProvider,
        killProvider,
        stdinProvider,
        operationsProvider,
        revaliProvider,
        zonaiDbProvider,
        versionsProvider,
        schemaVersionCheckProvider,
        dartSdkCheckProvider,
      },
    );

    return _LiveServer._(httpServer);
  }

  Future<void> close() => _httpServer.close(force: true);
}

// ===========================================================================
// Fixture plumbing -- matches the pattern every other file in this
// directory already uses (see e.g. admin_invite_runtime_e2e_test.dart).
// ===========================================================================

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

Directory _resolveFixture(String name) {
  var fixtureRoot = Directory(
    p.normalize(p.join(Directory.current.path, '..', '..', 'e2e', name)),
  );
  if (!fixtureRoot.existsSync()) {
    fixtureRoot = Directory(p.normalize('e2e/$name'));
  }
  expect(
    fixtureRoot.existsSync(),
    isTrue,
    reason: 'fixture missing at ${fixtureRoot.path}',
  );
  return fixtureRoot;
}

Set<ScopedRef<dynamic>> _e2eScopeOverrides(Settings settings) {
  return {
    fsProvider.overrideWith(LocalFileSystem.new),
    loggerProvider.overrideWith(() => Logger(level: .error)),
    settingsProvider.overrideWith(() => settings),
    processProvider,
    migrateProvider,
    mutationsProvider,
    cleanUpProvider,
    executableStopProvider,
    courierProvider,
  };
}

Future<void> _runZonai(Directory projectRoot, List<String> args) async {
  final zonaiEntry = p.normalize(
    p.join(Directory.current.path, 'bin', 'zonai.dart'),
  );
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['run', zonaiEntry, ...args],
    workingDirectory: projectRoot.path,
    environment: _forceWorkersEnv,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
}

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
  required String packageName,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: $packageName
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaRoot)}
''');
}

void _copyTree(Directory source, Directory destination) {
  for (final entity in source.listSync(recursive: true)) {
    final relative = p.relative(entity.path, from: source.path);
    if (relative.startsWith('.zonai') || relative == '.dart_tool') {
      continue;
    }
    final targetPath = p.join(destination.path, relative);
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(targetPath)).createSync(recursive: true);
      entity.copySync(targetPath);
    }
  }
}
