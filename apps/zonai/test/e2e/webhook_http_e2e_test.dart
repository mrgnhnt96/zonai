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
import 'package:zonai_schema/zonai_schema.dart';

import '../../lib/gen/server/.revali/server/server.dart' as gen_server;
import '../support/temp_directory.dart';
import '../support/zonai_cli.dart';

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
    late _LiveServer server;
    late http.Client client;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = _resolveFixture('webhook_repro');
      projectRoot = createCanonicalTempSync('zonai_webhook_http_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(
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
        webhooksProvider,
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
