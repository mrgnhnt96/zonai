import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/zonai_schema.dart';

import '../../lib/gen/server/.revali/server/server.dart' as gen_server;
import '../support/temp_directory.dart';

/// An API token over a REAL socket, against the actual generated server
/// (`apps/zonai/lib/gen/server`, the same code `zonai compile`/`zonai serve`
/// embeds).
///
/// Everything below `_extractJwt` is already covered by unit tests, and all
/// of it passed while the credential had never once been presented as an
/// `Authorization: Bearer` header. That is the gap this file closes, and the
/// reason it is worth its cost: the design's central promise -- *a token
/// works until its row says otherwise* -- is a statement about a live server
/// answering consecutive requests, and no test that stops at `ZonaiDb` can
/// make it.
///
/// The fixture is `e2e/data_plane_access_repro`, unmodified, because it
/// already carries the three shapes this needs:
///  - `admins`: `AsAdmin`, so it can mint the control JWT.
///  - `users`: an auth collection that is **not** `AsAdmin`, and whose rules
///    are the framework defaults -- so only an admin passes them. That makes
///    `/db/list?table=users` a clean admin/not-admin discriminator.
///  - `notes`: permissive table rules, per-row ownership rules, so a bound
///    token can be seen acting *as* its user rather than merely being
///    accepted.
///
/// See `admin_invite_http_oauth_e2e_test.dart` for why `gen_server.createServer`
/// is called in-process rather than shelling out to `zonai serve`, and why
/// this lives in its own file (and so its own isolate) rather than as a second
/// `group()` beside another fixture: `zonaiDbProvider`/`operationsProvider`
/// cache a module-level singleton across `runMergedScopedFuture` calls, and a
/// second fixture in the same isolate would silently reuse the first one's.
///
/// That same singleton is what lets [_ApiTokenFixture.mint] reach the server's
/// own `ZonaiDb` from the test: minting is a CLI-side operation with no HTTP
/// route (deliberately -- see `api_token_table_rules.dart`), so a token has to
/// be created in-process and then presented over the wire.
void main() {
  group('API token HTTP e2e (e2e/data_plane_access_repro)', () {
    late Directory projectRoot;
    late Settings settings;
    late _LiveServer server;
    late http.Client client;
    late String adminJwt;
    late String userId;
    final unique = DateTime.now().microsecondsSinceEpoch;

    Future<T> withDb<T>(Future<T> Function(ZonaiDb db) body) {
      return runMergedScopedFuture(
        () async => body(zonaiDB),
        override: _serverScopeOverrides(settings),
      );
    }

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      final fixtureRoot = _resolveFixture('data_plane_access_repro');
      projectRoot = createCanonicalTempSync('zonai_api_token_http_e2e_');
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

      settings = await runMergedScopedFuture(
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

      adminJwt = await _signUp(
        client,
        server,
        table: 'admins',
        email: 'token-admin-$unique@example.com',
        password: 'admin-password-1',
      );
      final user = await _signUpUser(
        client,
        server,
        table: 'users',
        email: 'token-user-$unique@example.com',
        password: 'user-password-1',
      );
      userId = user.id;

      // Two notes: one the bound token owns, one an UNBOUND token owns.
      //
      // An unbound token's `jwt.userId` is `ApiTokenJwt.sentinel`, and
      // `NoteRowRules` is ownership-based, so the sentinel is a real owner as
      // far as the rules are concerned -- which is the only way an unbound
      // token can be shown reading rows from an ownership-scoped collection
      // at all. `/db/list` fails the WHOLE call when any row in the page is
      // denied (`_requireRowsAccess`), so every `notes` read below carries a
      // `where` that keeps the other owner's row out of the page.
      for (final (title, owner) in [
        ('owned-by-$unique', userId),
        ('service-note-$unique', ApiTokenJwt.sentinel),
      ]) {
        final note = await client.post(
          server.uri('/db'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $adminJwt',
          },
          body: jsonEncode({
            'table': 'notes',
            'object': {'title': title, 'owner_id': owner},
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

    /// `GET /db/list` as [token], whatever kind of credential it is.
    Future<http.Response> list(String token, String table, {String? owner}) {
      return client.get(
        server.uri('/db/list', {
          'body': jsonEncode({
            'table': table,
            if (owner != null) 'where': Eq('owner_id', owner).toJson(),
          }),
        }),
        headers: {'authorization': 'Bearer $token'},
      );
    }

    Future<String> mint({
      required String name,
      required Set<String> tables,
      required Set<TableOperation> operations,
      bool? admin,
      String? boundTable,
      String? boundUserId,
    }) async {
      return await withDb((db) async {
        final minted = await db.createApiToken(
          name: '$name-$unique',
          scope: ApiTokenScope(
            tables: tables,
            operations: operations,
            admin: admin ?? true,
          ),
          createdBy: '__cli__',
          boundTable: boundTable,
          boundUserId: boundUserId,
        );
        return minted.secret;
      });
    }

    // -----------------------------------------------------------------
    // The header actually authenticates.
    // -----------------------------------------------------------------

    test('an opaque zonai_pat_ header reads an in-scope collection', () async {
      if (!_runningOnDartVm) return;

      final token = await mint(
        name: 'reader',
        tables: {'users'},
        operations: {TableOperation.view, TableOperation.list},
      );
      expect(token, startsWith(ApiTokenSecret.prefix));

      final response = await list(token, 'users');

      expect(response.statusCode, 200, reason: response.body);
      expect(response.body, contains('token-user-$unique@example.com'));

      // The sanitizer runs for a token exactly as it does for a JWT: the
      // password column is a secret, and so is every token's own hash.
      expect(response.body, isNot(contains('password')));
      expect(response.body, isNot(contains('token_hash')));
    });

    test('the same request is denied when the token is not an admin', () async {
      if (!_runningOnDartVm) return;

      // The control for the test above: `users` carries the framework's
      // default rules, which admit only an admin. So the 200 there is the
      // admin default doing the work, not a permissive fixture.
      final token = await mint(
        name: 'reader-no-admin',
        tables: {'users'},
        operations: {TableOperation.view, TableOperation.list},
        admin: false,
      );

      final response = await list(token, 'users');

      expect(response.statusCode, 403, reason: response.body);
    });

    // -----------------------------------------------------------------
    // The scope gate, and its refusal being indistinguishable from a
    // rules denial -- design §12: a token must not be able to map the
    // schema by watching which refusal it gets.
    // -----------------------------------------------------------------

    test(
      'an out-of-scope table is refused exactly as a rule refuses',
      () async {
        if (!_runningOnDartVm) return;

        final scoped = await mint(
          name: 'notes-only',
          tables: {'notes'},
          operations: {TableOperation.view, TableOperation.list},
        );
        final ruleDenied = await mint(
          name: 'rule-denied',
          tables: {'users'},
          operations: {TableOperation.view, TableOperation.list},
          admin: false,
        );

        // In scope, so the gate lets it through to the rules -- and the
        // rules then hand back the row this token owns.
        final inScope = await list(
          scoped,
          'notes',
          owner: ApiTokenJwt.sentinel,
        );
        expect(inScope.statusCode, 200, reason: inScope.body);
        expect(inScope.body, contains('service-note-$unique'));

        final outOfScope = await list(scoped, 'users');
        final denied = await list(ruleDenied, 'users');

        expect(outOfScope.statusCode, denied.statusCode);
        expect(outOfScope.body, denied.body);
        expect(outOfScope.statusCode, 403);
      },
    );

    test('an out-of-scope operation is refused the same way', () async {
      if (!_runningOnDartVm) return;

      final readOnly = await mint(
        name: 'read-only',
        tables: {'notes'},
        operations: {TableOperation.view, TableOperation.list},
      );

      final created = await client.post(
        server.uri('/db'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $readOnly',
        },
        body: jsonEncode({
          'table': 'notes',
          'object': {'title': 'should-not-exist-$unique', 'owner_id': userId},
        }),
      );

      expect(created.statusCode, 403, reason: created.body);
      expect(jsonDecode(created.body), {'error': 'Forbidden'});

      // And nothing was written: the gate runs before the operation, not
      // after it.
      final all = await list(
        await mint(
          name: 'verifier',
          tables: {'notes'},
          operations: {TableOperation.view, TableOperation.list},
        ),
        'notes',
        owner: userId,
      );
      expect(all.body, isNot(contains('should-not-exist-$unique')));
    });

    test('"*" reaches no internal table', () async {
      if (!_runningOnDartVm) return;

      final wildcard = await mint(
        name: 'wildcard',
        tables: {ApiTokenScope.wildcard},
        operations: TableOperation.values.toSet(),
      );

      // The wildcard genuinely is wide -- both app collections answer.
      expect((await list(wildcard, 'users')).statusCode, 200);
      expect(
        (await list(wildcard, 'notes', owner: ApiTokenJwt.sentinel)).statusCode,
        200,
      );

      for (final table in const ['_api_tokens', '_jwt', '_auth_challenges']) {
        final response = await list(wildcard, table);
        expect(
          response.statusCode,
          403,
          reason: '$table answered ${response.statusCode}: ${response.body}',
        );
        expect(response.body, isNot(contains('zonai_pat_')));
        expect(response.body, isNot(contains('token_hash')));
      }
    });

    // -----------------------------------------------------------------
    // The property the whole "no expiry" design rests on.
    // -----------------------------------------------------------------

    test('revoking stops the very next request, with no restart', () async {
      if (!_runningOnDartVm) return;

      final token = await mint(
        name: 'revoke-me',
        tables: {'users'},
        operations: {TableOperation.view, TableOperation.list},
      );

      expect((await list(token, 'users')).statusCode, 200);

      final row = await withDb(
        (db) async => (await db.listApiTokens()).firstWhere(
          (row) => row.name == 'revoke-me-$unique',
        ),
      );
      await withDb((db) => db.revokeApiToken(id: row.id.value));

      final after = await list(token, 'users');
      expect(after.statusCode, 401, reason: after.body);
    });

    // -----------------------------------------------------------------
    // Default-deny on every route family that is not the data API.
    // -----------------------------------------------------------------

    test('every non-data route refuses the token outright', () async {
      if (!_runningOnDartVm) return;

      final wildcard = await mint(
        name: 'everything',
        tables: {ApiTokenScope.wildcard},
        operations: TableOperation.values.toSet(),
      );
      final headers = {'authorization': 'Bearer $wildcard'};

      final members = await client.get(
        server.uri('/admin/members'),
        headers: headers,
      );
      final purge = await client.post(
        server.uri('/dashboard/maintenance/purge-table'),
        headers: {...headers, 'content-type': 'application/json'},
        body: jsonEncode({'table': 'notes'}),
      );

      // The same admin JWT that mints tokens succeeds here, so the refusals
      // below are about the credential and not about the route.
      expect(
        (await client.get(
          server.uri('/admin/members'),
          headers: {'authorization': 'Bearer $adminJwt'},
        )).statusCode,
        200,
      );

      for (final MapEntry(key: route, value: response) in {
        '/admin/members': members,
        '/dashboard/maintenance/purge-table': purge,
      }.entries) {
        expect(
          response.statusCode,
          anyOf(401, 403),
          reason: '$route answered ${response.statusCode}: ${response.body}',
        );
        // A refusal, not a crash: a 500 here would mean the default-deny is
        // an unhandled exception rather than an answer, and its body would
        // carry whatever the framework decided to say.
        expect(response.body, isNot(contains('#0')));
        expect(response.body, isNot(contains('Internal server error')));
      }
    });

    // -----------------------------------------------------------------
    // The dashboard's own route family: the only path that mints, because
    // `/db` structurally cannot be one.
    // -----------------------------------------------------------------

    test(
      'an admin mints, lists, revokes and deletes over /admin/tokens',
      () async {
        if (!_runningOnDartVm) return;

        final admin = {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminJwt',
        };

        final created = await client.post(
          server.uri('/admin/tokens'),
          headers: admin,
          body: jsonEncode({
            'name': 'dashboard-minted-$unique',
            'tables': ['users'],
            'operations': ['view', 'list'],
          }),
        );
        expect(created.statusCode, 200, reason: created.body);

        final row = _asMap(created);
        final secret = row['token']! as String;
        final id = row['id']! as String;

        // The plaintext is real: it authenticates on the next request, against
        // a route the minting one never touched.
        expect(secret, startsWith(ApiTokenSecret.prefix));
        expect((await list(secret, 'users')).statusCode, 200);

        // The row is an admin without anything asking for it -- the CLI's
        // default, reached through a second door.
        expect((row['scope']! as Map)['admin'], isTrue);
        expect((row['scope']! as Map)['canEdit'], isFalse);
        // And it records WHO, not `__cli__`.
        expect(row['createdBy'], isNot('__cli__'));
        expect(row['tokenPrefix'], isNotNull);

        final listed = await client.get(
          server.uri('/admin/tokens'),
          headers: admin,
        );
        expect(listed.statusCode, 200, reason: listed.body);
        expect(listed.body, contains('dashboard-minted-$unique'));
        // Shown once, and once only: nothing on the server can produce it again.
        expect(listed.body, isNot(contains(secret)));
        expect(listed.body, isNot(contains('tokenHash')));

        final revoked = await client.post(
          server.uri('/admin/tokens/$id/revoke'),
          headers: admin,
        );
        expect(revoked.statusCode, 200, reason: revoked.body);
        expect(_asMap(revoked)['revokedAt'], isNotNull);
        // On the very next request, with no restart.
        expect((await list(secret, 'users')).statusCode, 401);

        final deleted = await client.send(
          http.Request('DELETE', server.uri('/admin/tokens/$id'))
            ..headers['authorization'] = 'Bearer $adminJwt',
        );
        expect(deleted.statusCode, anyOf(200, 204), reason: '$deleted');

        final after = await client.get(
          server.uri('/admin/tokens'),
          headers: admin,
        );
        expect(after.body, isNot(contains('dashboard-minted-$unique')));
      },
    );

    test('an API token cannot mint a token', () async {
      if (!_runningOnDartVm) return;

      // The property the whole route family rests on. `_api_tokens` denies
      // `create` to everyone through `/db`, so this route is the only way in
      // -- and its gate uses `parseJwt` without `allowApiToken`, so the
      // credential is refused rather than scoped.
      final wildcard = await mint(
        name: 'would-be-minter',
        tables: {ApiTokenScope.wildcard},
        operations: TableOperation.values.toSet(),
      );

      for (final response in [
        await client.get(
          server.uri('/admin/tokens'),
          headers: {'authorization': 'Bearer $wildcard'},
        ),
        await client.post(
          server.uri('/admin/tokens'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $wildcard',
          },
          body: jsonEncode({
            'name': 'escalation-$unique',
            'tables': ['*'],
            'operations': ['view', 'list', 'create', 'update', 'delete'],
          }),
        ),
      ]) {
        expect(
          response.statusCode,
          anyOf(401, 403),
          reason: '${response.statusCode}: ${response.body}',
        );
      }

      // And nothing was minted by the attempt.
      final listed = await client.get(
        server.uri('/admin/tokens'),
        headers: {'authorization': 'Bearer $adminJwt'},
      );
      expect(listed.body, isNot(contains('escalation-$unique')));
    });

    // -----------------------------------------------------------------
    // A bound token is never more privileged than the row it acts as.
    // -----------------------------------------------------------------

    test('a token bound to a non-admin row is not an admin', () async {
      if (!_runningOnDartVm) return;

      final bound = await mint(
        name: 'bound',
        tables: {'users', 'notes'},
        operations: {TableOperation.view, TableOperation.list},
        boundTable: 'users',
        boundUserId: userId,
      );

      // It authenticates, and it authenticates AS that user: `notes` has
      // permissive table rules and per-row ownership rules, so seeing the
      // row means `jwt.userId` really is the bound user's.
      final notes = await list(bound, 'notes', owner: userId);
      expect(notes.statusCode, 200, reason: notes.body);
      expect(notes.body, contains('owned-by-$unique'));

      // And it is not an admin, though its row was minted as one: `users`
      // is not an `AsAdmin` collection, and the clamp takes the stricter of
      // the two. The unbound token in the first test proves the same
      // request answers 200 for a token that really is an admin.
      final users = await list(bound, 'users');
      expect(users.statusCode, 403, reason: users.body);
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
  return (await _signUpUser(
    client,
    server,
    table: table,
    email: email,
    password: password,
  )).jwt;
}

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
