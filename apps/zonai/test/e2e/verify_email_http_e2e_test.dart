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
import '../support/zonai_cli.dart';

/// `POST /auth/verify-email`, over a real socket against the generated server.
///
/// With no body, the route is "send the signed-in caller a verification email
/// for their own address": the controller takes `@Body() VerifyEmailAuthBody?`
/// and `auth_handler.sendVerifyEmail` hands `zonaiDB` a null payload, which
/// resolves the table and address from the bearer.
///
/// It never got that far. The route's `@BodyRateLimit<VerifyEmailAuthBody>`
/// guard read the body as a non-nullable `VerifyEmailAuthBody`, revali reads
/// an absent body as `{}`, and the generated guard's only parse arm is
/// `Map data when data.isNotEmpty`, so every body-less call answered 400
/// `MissingArgumentException: key: body ... actual: _Map<String, dynamic>`
/// before the handler ran. That is what `zonai_client`'s
/// `auth.sendVerifyEmail()` sends with no arguments (reported against
/// v0.10.1), and nothing exercised the route at all.
///
/// Uses `e2e/admin_password_update_repro` unchanged: its `users` table has
/// `PasswordAuth`, so a real sign-up mints the bearer. Its own file, so its own
/// isolate -- see `admin_invite_http_oauth_e2e_test.dart`'s doc comment.
void main() {
  group('verify-email HTTP e2e (e2e/admin_password_update_repro)', () {
    late Directory projectRoot;
    late _LiveServer server;
    late http.Client client;
    final unique = DateTime.now().microsecondsSinceEpoch;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = _resolveFixture('admin_password_update_repro');
      projectRoot = createCanonicalTempSync('zonai_verify_email_http_e2e_');
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

    /// Exactly what `revali_client` puts on the wire for a null body: no
    /// body and no content-type.
    Future<http.Response> verifyEmailWithoutBody(String bearer) {
      return client.post(
        server.uri('/auth/verify-email'),
        headers: {'authorization': 'Bearer $bearer'},
      );
    }

    test(
      'a signed-in caller can ask for their own verification email with no body',
      () async {
        if (!_runningOnDartVm) return;

        final bearer = await _signUp(
          client,
          server,
          table: 'users',
          email: 'verify-self-$unique@example.com',
          password: 'verify-self-pw-1',
        );

        final first = await verifyEmailWithoutBody(bearer);
        expect(first.statusCode, 200, reason: first.body);

        // Proof the first call reached the send, not just a 200 from
        // somewhere: it stored a challenge, so a second one inside a minute
        // is refused by the auth layer's own cooldown. That refusal is the
        // auth layer's message, not the route rate limiter's.
        final second = await verifyEmailWithoutBody(bearer);
        expect(second.statusCode, 429, reason: second.body);
        expect(second.body, contains('before sending a new code'));
      },
    );

    test('with a body naming the caller, the same route still works', () async {
      if (!_runningOnDartVm) return;

      final email = 'verify-body-$unique@example.com';
      final bearer = await _signUp(
        client,
        server,
        table: 'users',
        email: email,
        password: 'verify-body-pw-1',
      );

      final response = await client.post(
        server.uri('/auth/verify-email'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $bearer',
        },
        body: jsonEncode({'email': email, 'table': 'users'}),
      );
      expect(response.statusCode, 200, reason: response.body);
    });
  });
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
  final result = await runZonaiCli(
    args,
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
