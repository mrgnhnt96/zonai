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
import 'package:zonai_schema/zonai_schema.dart';

import '../support/e2e_fixture.dart';
import '../support/live_server.dart';
import '../support/temp_directory.dart';

/// HTTP-layer proof of `POST /hooks/:name` over a real socket, against the
/// generated server, its rate-limit guard and the real compiled webhooks
/// worker (`e2e/webhook_repro`).
///
/// The controller test in apps/server stubs the worker, so only this file
/// shows that a delivery's queued writes commit as the server, that a throw
/// drops them, and that the route is rate limited.
///
/// In its own file for the reason `signup_gate_http_e2e_test.dart` gives:
/// providers cache a module-level singleton per isolate.
void main() {
  group('webhook HTTP e2e (e2e/webhook_repro)', () {
    late Directory projectRoot;
    late LiveServer server;
    late http.Client client;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = resolveFixture('webhook_repro');
      projectRoot = createCanonicalTempSync('zonai_webhook_http_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      copyFixtureTree(fixtureRoot, projectRoot);
      rewriteFixturePubspec(
        projectRoot: projectRoot,
        repoRoot: repoRoot,
        packageName: 'zonai_webhook_repro',
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

    Future<http.Response> deliver(
      String name, {
      String body = '',
      Map<String, String> headers = const {'x-secret': 'letmein'},
    }) => client.post(server.uri('/hooks/$name'), headers: headers, body: body);

    Future<List<Object?>> titlesWhere(String title) async {
      final response = await client.get(
        server.uri('/db/list', {
          'body': jsonEncode({
            'table': 'posts',
            'where': Eq('title', title).toJson(),
          }),
        }),
      );
      expect(response.statusCode, 200, reason: response.body);
      final items = switch (jsonDecode(response.body)) {
        {'data': {'items': final List<dynamic> items}} => items,
        {'data': final List<dynamic> items} => items,
        final other => fail('unexpected list body: $other'),
      };
      return [for (final item in items) (item as Map)['title']];
    }

    test('a delivery writes a row the anonymous caller could not', () async {
      if (!_runningOnDartVm) return;

      // posts creates are admin-only: the caller cannot make this row itself.
      final anonymous = await client.post(
        server.uri('/db'),
        headers: _json,
        body: jsonEncode({
          'table': 'posts',
          'object': {'title': 'by-anonymous'},
        }),
      );
      expect(anonymous.statusCode, isNot(200), reason: anonymous.body);
      expect(await titlesWhere('by-anonymous'), isEmpty);

      final response = await deliver('echo', body: 'héllo');

      expect(response.statusCode, 200, reason: response.body);
      expect(response.headers['content-type'], startsWith('text/plain'));
      // 6 bytes: the body arrives as sent, é is two of them.
      expect(response.body, '6 bytes from 127.0.0.1');
      expect(await titlesWhere('héllo'), ['héllo']);
    });

    test(
      "answers with the webhook's own refusal, and writes nothing",
      () async {
        if (!_runningOnDartVm) return;

        final response = await deliver(
          'echo',
          body: 'no-secret',
          headers: const {},
        );

        expect(response.statusCode, 401, reason: response.body);
        expect(response.body, 'bad secret');
        expect(await titlesWhere('no-secret'), isEmpty);
      },
    );

    test('a name with no webhook is a 404', () async {
      if (!_runningOnDartVm) return;

      final response = await deliver('stripe');

      expect(response.statusCode, 404, reason: response.body);
    });

    test('a throw is a 500, and the write it queued is dropped', () async {
      if (!_runningOnDartVm) return;

      final response = await deliver('boom');

      expect(response.statusCode, 500, reason: response.body);
      expect(await titlesWhere('from-boom'), isEmpty);
    });

    // Last: it spends this IP's allowance.
    test('is rate limited per IP', () async {
      if (!_runningOnDartVm) return;

      // The default policy allows 100 a minute; the tests above used some.
      int? limitedAt;
      for (var i = 1; i <= 110; i++) {
        final response = await deliver('stripe');
        if (response.statusCode == 429) {
          limitedAt = i;
          break;
        }
        expect(response.statusCode, 404, reason: response.body);
      }

      expect(limitedAt, isNotNull, reason: 'never limited in 110 requests');
    });
  });
}

const _json = {'content-type': 'application/json'};

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
