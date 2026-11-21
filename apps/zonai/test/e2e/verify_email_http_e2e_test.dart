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
import 'package:zonai_logger/zonai_logger.dart';

import '../support/e2e_fixture.dart';
import '../support/live_server.dart';
import '../support/temp_directory.dart';

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
    late LiveServer server;
    late http.Client client;
    final unique = DateTime.now().microsecondsSinceEpoch;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = resolveFixture('admin_password_update_repro');
      projectRoot = createCanonicalTempSync('zonai_verify_email_http_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      copyFixtureTree(fixtureRoot, projectRoot);
      rewriteFixturePubspec(
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
        await runZonaiInFixture(projectRoot, [
          'compile',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await runZonaiInFixture(projectRoot, [
          'db',
          'migrate',
          'generate',
          '--name',
          'initialize',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await runZonaiInFixture(projectRoot, [
          'db',
          'migrate',
          'apply',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
      }, override: _e2eScopeOverrides(settings));

      server = await LiveServer.start(settings);
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
  LiveServer server, {
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
// Fixture plumbing -- matches the pattern every other file in this
// directory already uses (see e.g. admin_invite_runtime_e2e_test.dart).
// ===========================================================================

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

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
