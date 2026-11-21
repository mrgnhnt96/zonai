import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../support/e2e_fixture.dart';
import '../support/live_server.dart';
import '../support/temp_directory.dart';

/// Anonymous accounts over a REAL socket, against the actual generated server
/// (`apps/zonai/lib/gen/server`, the code `zonai serve` embeds).
///
/// `anonymous_auth_e2e_test.dart` proves the flows at the `ZonaiDb` layer.
/// This proves what only a live server can: the routes and their guards, the
/// `X-Auth` header a client picks the session up from, the structured
/// `email_in_use` 409 on the wire, that the old bearer really stops working
/// after an upgrade, and that the creation rate limit actually trips.
///
/// See `api_token_http_e2e_test.dart` for why the server is bound in-process
/// and why this lives in its own file (and so its own isolate).
void main() {
  group('anonymous auth HTTP e2e (e2e/anonymous_auth)', () {
    late Directory projectRoot;
    late Settings settings;
    late LiveServer server;
    late http.Client client;
    final unique = DateTime.now().microsecondsSinceEpoch;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = resolveFixture('anonymous_auth');
      projectRoot = createCanonicalTempSync('zonai_anonymous_auth_http_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      copyFixtureTree(fixtureRoot, projectRoot);
      rewriteFixturePubspec(
        projectRoot: projectRoot,
        repoRoot: repoRoot,
        packageName: 'zonai_anonymous_auth_fixture',
      );

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
      ], workingDirectory: projectRoot.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}\n${pubGet.stdout}');

      settings = await runMergedScopedFuture(
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

      // The upgrade code is the fixed insecure-test-mode one. In-process, so
      // this reaches the server's own mutator.
      debugInsecureTestMode = true;
      server = await LiveServer.start(settings);
      client = http.Client();
    });

    tearDownAll(() async {
      if (!_runningOnDartVm) return;
      debugInsecureTestMode = null;
      client.close();
      await server.close();
      deleteTempDirectory(projectRoot);
    });

    Future<http.Response> post(
      String path,
      Map<String, Object?> body, {
      String? bearer,
    }) {
      return client.post(
        server.uri(path),
        headers: {
          'content-type': 'application/json',
          'authorization': ?switch (bearer) {
            null => null,
            final token => 'Bearer $token',
          },
        },
        body: jsonEncode(body),
      );
    }

    Future<Map<String, dynamic>> createAnonymous() async {
      final response = await post('/auth/anonymous', {'table': 'users'});
      expect(response.statusCode, 200, reason: response.body);
      return _asMap(response);
    }

    test(
      'create, write, upgrade: same id, and the old bearer is retired',
      () async {
        if (!_runningOnDartVm) return;

        final response = await post('/auth/anonymous', {'table': 'users'});
        expect(response.statusCode, 200, reason: response.body);
        final created = _asMap(response);
        final anonymousToken = created['accessToken'] as String;
        final userId = (created['user'] as Map)['id'] as String;

        expect(response.headers['x-auth'], anonymousToken);
        expect((created['user'] as Map)['email'], isNull);
        expect(created['anonymousCredential'], startsWith('zonai_anon_'));

        final note = await post('/db', {
          'table': 'notes',
          'object': {'owner_id': userId, 'body': 'before upgrade'},
        }, bearer: anonymousToken);
        expect(note.statusCode, 200, reason: note.body);

        final email = 'wire-$unique@example.com';
        final requested = await post('/auth/upgrade', {
          'email': email,
        }, bearer: anonymousToken);
        expect(requested.statusCode, 200, reason: requested.body);

        final confirmed = await post('/auth/upgrade/confirm', {
          'email': email,
          'code': kInsecureTestOtp,
        }, bearer: anonymousToken);
        expect(confirmed.statusCode, 200, reason: confirmed.body);
        final upgraded = _asMap(confirmed);
        expect((upgraded['user'] as Map)['id'], userId);
        expect((upgraded['user'] as Map)['email'], email);
        expect(confirmed.headers['x-auth'], upgraded['accessToken']);

        // The anonymous bearer is dead; the upgraded one reads the same note.
        final withOld = await client.get(
          server.uri('/db/list', {
            'body': jsonEncode({
              'table': 'notes',
              'where': {
                'owner_id': {'eq': userId},
              },
            }),
          }),
          headers: {'authorization': 'Bearer $anonymousToken'},
        );
        expect(withOld.statusCode, 401, reason: withOld.body);

        final withNew = await client.get(
          server.uri('/db/list', {
            'body': jsonEncode({
              'table': 'notes',
              'where': {
                'owner_id': {'eq': userId},
              },
            }),
          }),
          headers: {'authorization': 'Bearer ${upgraded['accessToken']}'},
        );
        expect(withNew.statusCode, 200, reason: withNew.body);
        expect(withNew.body, contains('before upgrade'));
      },
    );

    test('the credential resumes the account over the wire', () async {
      if (!_runningOnDartVm) return;

      final created = await createAnonymous();
      final resumed = await post('/auth/anonymous/resume', {
        'credential': created['anonymousCredential'],
      });
      expect(resumed.statusCode, 200, reason: resumed.body);
      expect(
        (_asMap(resumed)['user'] as Map)['id'],
        (created['user'] as Map)['id'],
      );

      final forged = await post('/auth/anonymous/resume', {
        'credential': 'zonai_anon_${'0' * 64}',
      });
      expect(forged.statusCode, 401, reason: forged.body);
    });

    test('a taken address answers the structured email_in_use 409', () async {
      if (!_runningOnDartVm) return;

      final taken = 'taken-$unique@example.com';
      final owner = await post('/auth/sign-up', {
        'table': 'users',
        'type': 'signUp',
        'email': taken,
        'password': 'first-owner-password-1',
      });
      expect(owner.statusCode, 200, reason: owner.body);

      final anonymous = await createAnonymous();
      final token = anonymous['accessToken'] as String;

      final requested = await post('/auth/upgrade', {
        'email': taken,
      }, bearer: token);
      expect(requested.statusCode, 200, reason: requested.body);

      final confirmed = await post('/auth/upgrade/confirm', {
        'email': taken,
        'code': kInsecureTestOtp,
      }, bearer: token);
      expect(confirmed.statusCode, 409, reason: confirmed.body);
      expect(jsonDecode(confirmed.body), {
        'error': containsPair('code', 'email_in_use'),
      });
    });

    // Last: it spends the (IP, table) creation budget the tests above share.
    test('creating anonymous accounts is rate limited', () async {
      if (!_runningOnDartVm) return;

      var created = 0;
      http.Response? refused;
      for (var i = 0; i < 40 && refused == null; i++) {
        final response = await post('/auth/anonymous', {'table': 'users'});
        if (response.statusCode == 429) {
          refused = response;
        } else {
          expect(response.statusCode, 200, reason: response.body);
          created++;
        }
      }

      expect(refused, isNotNull, reason: 'never throttled after $created');
      // The default is 30 an hour; the tests above spent some of it.
      expect(created, lessThanOrEqualTo(30));
    });
  });
}

// ===========================================================================
// Shared HTTP helpers.
// ===========================================================================

/// Revali's default response handler wraps a returned `Map` body in a
/// `{"data": ...}` envelope; this unwraps it so callers can read the
/// handler's own return shape directly.
Map<String, dynamic> _asMap(http.Response response) {
  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  return switch (decoded) {
    {'data': final Map<String, dynamic> data} => data,
    _ => decoded,
  };
}

// ===========================================================================
// Fixture plumbing -- matches the pattern every other file in this
// directory already uses.
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
