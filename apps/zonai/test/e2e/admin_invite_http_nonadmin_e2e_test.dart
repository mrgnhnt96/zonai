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
/// embeds), that a genuinely authenticated NON-admin caller is refused on
/// every `/admin/**` route -- design §4 item 1's table-scoping half.
///
/// This is the gap `admin_invite_runtime_e2e_test.dart` and
/// `apps/server/test/admin_routes_test.dart` both document explicitly and
/// neither can close: `e2e/oauth`'s one auth table is entirely admin, so it
/// cannot mint an authenticated non-admin JWT, and
/// `apps/server/routes/controllers/admin_controller.dart`'s own handler
/// tests only reach `mayActOnAdminTable` as a pure function, never through a
/// live route. `e2e/admin_password_update_repro` already carries a second,
/// non-`AsAdmin` `users` table alongside its `AsAdmin` `admins` table
/// (`e2e/admin_password_update_repro/lib/src/schemas/users.dart` vs
/// `admins.dart`) -- built for a different bug repro, but exactly the shape
/// needed here. A real `POST /auth/sign-up` against `users` mints a JWT that
/// is genuinely authenticated and genuinely not an admin, and this file
/// drives every `/admin/**` route with it over the wire.
///
/// See `admin_invite_http_oauth_e2e_test.dart`'s doc comment for why
/// `gen_server.createServer` is called in-process rather than shelling out
/// to `zonai serve`, and why this lives in its own file/isolate rather than
/// a second `group()` alongside that one:
/// `zonaiDbProvider`/`operationsProvider` et al. cache a module-level
/// singleton across `runMergedScopedFuture` calls within one isolate, and a
/// second fixture in the same file would silently reuse the first one's.
///
/// Neither fixture is modified, and neither is a new top-level `e2e/**`
/// directory -- see the sibling file's doc comment on why that matters for
/// this leaf's commit gate.
void main() {
  group(
    'admin invite HTTP e2e (non-admin caller, e2e/admin_password_update_repro)',
    () {
      late Directory projectRoot;
      late _LiveServer server;
      late http.Client client;
      final unique = DateTime.now().microsecondsSinceEpoch;

      setUpAll(() async {
        if (!_runningOnDartVm) return;

        final fixtureRoot = _resolveFixture('admin_password_update_repro');
        projectRoot = createCanonicalTempSync(
          'zonai_admin_invite_http_nonadmin_e2e_',
        );
        final repoRoot = fixtureRoot.parent.parent;
        _copyTree(fixtureRoot, projectRoot);
        _rewritePubspecPaths(
          projectRoot: projectRoot,
          repoRoot: repoRoot,
          packageName: 'zonai_admin_password_update_repro',
        );

        final pubGet = await Process.run(Platform.resolvedExecutable, const [
          'pub',
          'get',
        ], workingDirectory: projectRoot.path);
        expect(
          pubGet.exitCode,
          0,
          reason: '${pubGet.stderr}\n${pubGet.stdout}',
        );

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

      // -----------------------------------------------------------------
      // The gap named in the file doc comment: `admins` (AsAdmin) and
      // `users` (not) are two DIFFERENT AuthTables in the SAME project, so
      // a JWT minted against `users` really is authenticated -- and really
      // is not an admin. That is what `mayActOnAdminTable`'s
      // `jwt.admin.isAdmin != true` branch is checking, exercised here
      // through the real route, not as a pure-function call.
      // -----------------------------------------------------------------

      test(
        'a genuinely authenticated non-admin caller is refused on every '
        'admin route, while a real admin on the same routes succeeds',
        () async {
          if (!_runningOnDartVm) return;

          final nonAdminEmail = 'http-nonadmin-$unique@example.com';
          final nonAdminJwt = await _signUp(
            client,
            server,
            table: 'users',
            email: nonAdminEmail,
            password: 'nonadmin-pw-1',
          );

          final adminEmail = 'http-realadmin-$unique@example.com';
          final adminJwt = await _signUp(
            client,
            server,
            table: 'admins',
            email: adminEmail,
            password: 'realadmin-pw-1',
          );

          // The real admin succeeds on the read route -- the refusal below
          // is not a coincidental blanket-403.
          final asAdmin = await client.get(
            server.uri('/admin/members'),
            headers: {'authorization': 'Bearer $adminJwt'},
          );
          expect(asAdmin.statusCode, 200, reason: asAdmin.body);

          final asNonAdminMembers = await client.get(
            server.uri('/admin/members'),
            headers: {'authorization': 'Bearer $nonAdminJwt'},
          );
          expect(asNonAdminMembers.statusCode, 403);

          final asNonAdminInvite = await client.post(
            server.uri('/admin/invites'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $nonAdminJwt',
            },
            body: jsonEncode({'email': 'target-$unique@example.com'}),
          );
          expect(asNonAdminInvite.statusCode, 403);

          final asNonAdminRevoke = await client.send(
            http.Request(
              'DELETE',
              server.uri('/admin/invites/target-$unique@example.com'),
            )..headers['authorization'] = 'Bearer $nonAdminJwt',
          );
          expect(asNonAdminRevoke.statusCode, 403);

          final asNonAdminRemove = await client.send(
            http.Request('DELETE', server.uri('/admin/members/${adminEmail}'))
              ..headers['authorization'] = 'Bearer $nonAdminJwt',
          );
          expect(asNonAdminRemove.statusCode, 403);

          // The would-be victim of that last, refused call is still there.
          final stillAdmin = await client.get(
            server.uri('/admin/members'),
            headers: {'authorization': 'Bearer $adminJwt'},
          );
          expect(stillAdmin.statusCode, 200);
        },
      );
    },
  );
}

// ===========================================================================
// Shared HTTP helpers.
// ===========================================================================

Future<String> _signUp(
  http.Client client,
  _LiveServer server, {
  required String table,
  required String email,
  required String password,
}) async {
  final response = await client.post(
    server.uri('/auth/sign-up'),
    headers: const {'content-type': 'application/json'},
    body: jsonEncode({
      'table': table,
      'type': 'signUp',
      'email': email,
      'password': password,
    }),
  );
  expect(response.statusCode, 200, reason: '$table/$email: ${response.body}');
  return _asMap(response)['accessToken'] as String;
}

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
