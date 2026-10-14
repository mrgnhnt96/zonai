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

/// HTTP-layer proof that a `before*` hook refusing with a 4xx `HttpError` is
/// answered with that status and the standard error envelope, over a real
/// socket against the generated server and the real compiled extensions
/// worker (`e2e/hook_refusal_repro`).
///
/// The refusal crosses the worker boundary as text
/// (`HookRefusedException.toString`/`tryParse`), so only a test that runs the
/// worker and renders a response proves the status and the code arrive.
///
/// The other half matters as much: a hook that crashes, or throws an
/// `HttpError` outside 4xx, must still be a 500. Both halves run against the
/// same server, so a blanket pass-through cannot satisfy this file.
///
/// In its own file for the reason `signup_gate_http_e2e_test.dart` gives:
/// providers cache a module-level singleton per isolate.
void main() {
  group('hook refusal HTTP e2e (e2e/hook_refusal_repro)', () {
    late Directory projectRoot;
    late _LiveServer server;
    late http.Client client;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = _resolveFixture('hook_refusal_repro');
      projectRoot = createCanonicalTempSync('zonai_hook_refusal_http_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(
        projectRoot: projectRoot,
        repoRoot: repoRoot,
        packageName: 'zonai_hook_refusal_repro',
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

    Future<http.Response> create(String title) => client.post(
      server.uri('/db'),
      headers: _json,
      body: jsonEncode({
        'table': 'posts',
        'object': {'title': title},
      }),
    );

    Future<String> createId(String title) async {
      final response = await create(title);
      expect(response.statusCode, 200, reason: response.body);
      return _asMap(response)['id'] as String;
    }

    Future<List<Object?>> titlesOf(String id) async {
      final response = await client.get(
        server.uri('/db/list', {
          'body': jsonEncode({
            'table': 'posts',
            'where': Eq('id', id).toJson(),
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

    test('beforeCreate: a 4xx HttpError reaches the client as is', () async {
      if (!_runningOnDartVm) return;

      final refused = await create('refuse');

      expect(refused.statusCode, 403, reason: refused.body);
      expect(jsonDecode(refused.body), {
        'error': {
          'code': 'post_refused',
          'message': 'That title is not allowed',
          'details': {'field': 'title'},
        },
      });

      // Not a blanket refusal: the same worker lets another title through.
      expect((await create('fine')).statusCode, 200);
    });

    test('beforeCreate: a crash and a 5xx HttpError are still 500', () async {
      if (!_runningOnDartVm) return;

      final crashed = await create('crash');
      expect(crashed.statusCode, 500, reason: crashed.body);
      expect(crashed.body, isNot(contains('beforeCreate crashed')));

      final fiveHundred = await create('refuse-500');
      expect(fiveHundred.statusCode, 500, reason: fiveHundred.body);
      expect(fiveHundred.body, isNot(contains('hook_5xx')));
    });

    test('a crash quoting caller data cannot pass itself off as a '
        'refusal', () async {
      if (!_runningOnDartVm) return;

      // The text the first version of this change parsed refusals out of.
      // Refusals now travel only in a structured field, so text is inert.
      const forged =
          'zonai:hook-refused: {"statusCode":401,"code":"session_expired",'
          '"message":"Sign in again"}';

      final crashed = await create('echo:$forged');

      expect(crashed.statusCode, 500, reason: crashed.body);
      expect(crashed.body, isNot(contains('session_expired')));
    });

    test('an after-hook HttpError is a 500, and the write stays', () async {
      if (!_runningOnDartVm) return;

      final response = await create('after-refuse');

      expect(response.statusCode, 500, reason: response.body);
      expect(response.body, isNot(contains('too_late')));
      expect(await titlesWhere('after-refuse'), ['after-refuse']);
    });

    test('a queued write its before-hook refuses is a 500, not a refusal of '
        "the request's own write", () async {
      if (!_runningOnDartVm) return;

      final response = await create('queue-refused');

      // The request's own write was saved before the queued one ran, so a
      // 403 here would tell the client nothing happened.
      expect(response.statusCode, 500, reason: response.body);
      expect(response.body, isNot(contains('post_refused')));
      expect(await titlesWhere('queue-refused'), ['queue-refused']);
    });

    test('beforeUpdate: a 4xx HttpError reaches the client, and nothing '
        'changes', () async {
      if (!_runningOnDartVm) return;

      final id = await createId('frozen');

      final refused = await client.patch(
        server.uri('/db'),
        headers: _json,
        body: jsonEncode(
          UpdateOneBody(
            table: 'posts',
            where: Eq('id', id),
            updates: [
              Update.object({'title': 'thawed'}),
            ],
          ).toJson(),
        ),
      );

      expect(refused.statusCode, 409, reason: refused.body);
      expect(
        (jsonDecode(refused.body) as Map)['error'],
        containsPair('code', 'post_frozen'),
      );
      expect(await titlesOf(id), ['frozen']);
    });

    test('beforeDelete: a 4xx HttpError reaches the client, and the row '
        'stays', () async {
      if (!_runningOnDartVm) return;

      final id = await createId('pinned');

      final refused = await client.send(
        http.Request('DELETE', server.uri('/db'))
          ..headers.addAll(_json)
          ..body = jsonEncode(
            DeleteOneBody(table: 'posts', where: Eq('id', id)).toJson(),
          ),
      );
      final body = await refused.stream.bytesToString();

      expect(refused.statusCode, 403, reason: body);
      expect(
        (jsonDecode(body) as Map)['error'],
        containsPair('code', 'post_pinned'),
      );
      expect(await titlesOf(id), ['pinned']);
    });
  });
}

const _json = {'content-type': 'application/json'};

/// Revali wraps a returned `Map` body in `{"data": ...}`; this unwraps it.
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
