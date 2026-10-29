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

/// A `where` value that only *looks* numeric is matched as the string the
/// client sent, over a REAL socket against the actual generated server
/// (`apps/zonai/lib/gen/server`).
///
/// `GET /db`, `/db/list` and `/db/count` carry their payload as `?body=<json>`.
/// Revali coerces query values, and it used to coerce every string *inside*
/// that JSON too: an all-digit string past int64 -- a Costco or Walmart order
/// number, `'21102800905892610131829'` -- came out as a `double`, was bound as
/// a REAL, and an `eq` against the TEXT column it was stored in found nothing.
/// A get-then-create caller then POSTed a duplicate and hit the unique index's
/// 409. Leading-zero and dashed values survived the coercion, which is why
/// they are here as controls.
///
/// None of this is visible below the HTTP layer -- `Where.fromJson` and
/// `whereValueToParam` pass a string through untouched -- so it can only be
/// tested by sending the query string a client sends.
///
/// The fixture is `e2e/data_plane_access_repro`: `notes.title` is a TEXT
/// column, and `notes` is readable by the user whose id is in `owner_id`.
/// See `api_token_http_e2e_test.dart` for why the server runs in-process and
/// why this fixture lives in its own file (and so its own isolate).
void main() {
  group('long digit strings in ?body= (e2e/data_plane_access_repro)', () {
    late Directory projectRoot;
    late _LiveServer server;
    late http.Client client;
    late String userJwt;
    final unique = DateTime.now().microsecondsSinceEpoch;

    const titles = [
      '21102800905892610131829', // 23 digits, past int64 and past double
      '21369517979748791720', // 20 digits, past int64
      '07477349789323628418', // leading zero: was already kept as text
      '6215-2940-0164-3865', // dashes: was already kept as text
    ];

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = _resolveFixture('data_plane_access_repro');
      projectRoot = createCanonicalTempSync('zonai_long_digit_http_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(
        projectRoot: projectRoot,
        repoRoot: repoRoot,
        packageName: 'zonai_data_plane_access_repro',
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

      final user = await _signUpUser(
        client,
        server,
        table: 'users',
        email: 'digits-$unique@example.com',
        password: 'user-password-1',
      );
      userJwt = user.jwt;

      for (final title in titles) {
        final note = await client.post(
          server.uri('/db'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $userJwt',
          },
          body: jsonEncode({
            'table': 'notes',
            'object': {'title': title, 'owner_id': user.id},
          }),
        );
        expect(note.statusCode, 200, reason: note.body);
      }
    });

    tearDownAll(() async {
      if (!_runningOnDartVm) return;
      client.close();
      await server.close();
      deleteTempDirectory(projectRoot);
    });

    Future<http.Response> query(String path, Map<String, Object?> body) {
      return client.get(
        server.uri(path, {'body': jsonEncode(body)}),
        headers: {'authorization': 'Bearer $userJwt'},
      );
    }

    for (final title in titles) {
      group(title, () {
        test('GET /db finds the row by eq', () async {
          if (!_runningOnDartVm) return;

          final response = await query('/db', {
            'table': 'notes',
            'where': Eq('title', title).toJson(),
          });

          expect(response.statusCode, 200, reason: response.body);
          expect(_asMap(response)['title'], title);
        });

        test('GET /db/list finds the row by eq', () async {
          if (!_runningOnDartVm) return;

          final response = await query('/db/list', {
            'table': 'notes',
            'where': Eq('title', title).toJson(),
          });

          expect(response.statusCode, 200, reason: response.body);
          final items = _asMap(response)['items'] as List;
          expect(items.map((e) => (e as Map)['title']), [title]);
        });

        test('GET /db/list finds the row by in', () async {
          if (!_runningOnDartVm) return;

          final response = await query('/db/list', {
            'table': 'notes',
            'where': In('title', [title]).toJson(),
          });

          expect(response.statusCode, 200, reason: response.body);
          final items = _asMap(response)['items'] as List;
          expect(items.map((e) => (e as Map)['title']), [title]);
        });
      });
    }

    test('a ?body= that is not a JSON object is still a 400', () async {
      if (!_runningOnDartVm) return;

      for (final raw in ['not json', '[]', '{}', '42']) {
        final response = await client.get(
          server.uri('/db/list', {'body': raw}),
          headers: {'authorization': 'Bearer $userJwt'},
        );
        expect(response.statusCode, 400, reason: '$raw: ${response.body}');
      }

      final missing = await client.get(
        server.uri('/db/list'),
        headers: {'authorization': 'Bearer $userJwt'},
      );
      expect(missing.statusCode, 400, reason: missing.body);
    });
  });
}

// ===========================================================================
// Shared HTTP helpers.
// ===========================================================================

Future<({String jwt, String id})> _signUpUser(
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
  final data = _asMap(response);
  return (
    jwt: data['accessToken'] as String,
    id: (data['user'] as Map)['id'] as String,
  );
}

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
// A real, live server, bound in-process.
// ===========================================================================

class _LiveServer {
  _LiveServer._(this._httpServer);

  final HttpServer _httpServer;

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.http('127.0.0.1:${_httpServer.port}', path, query);

  static Future<_LiveServer> start(Settings settings) async {
    final httpServer = await runMergedScopedFuture(
      () => gen_server.createServer(null, const []),
      override: _serverScopeOverrides(settings),
    );

    return _LiveServer._(httpServer);
  }

  Future<void> close() => _httpServer.close(force: true);
}

/// `apps/zonai/lib/src/bootstrap.dart`'s `runZonai` registration set, which is
/// also what lets a test-side `zonaiDB` resolve to the server's own instance:
/// `zonaiDbProvider` caches a module-level singleton, so registering it
/// unoverridden here hands back the same database the routes are answering
/// from.
Set<ScopedRef<dynamic>> _serverScopeOverrides(Settings settings) => {
  argsProvider.overrideWith(
    () => Args.parse(const ['--host=127.0.0.1', '--port=0']),
  ),
  fsProvider.overrideWith(LocalFileSystem.new),
  loggerProvider.overrideWith(() => Logger(level: .error)),
  settingsProvider.overrideWith(() => settings),
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
};

// ===========================================================================
// Fixture plumbing -- matches the pattern every other file in this
// directory already uses.
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
