import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../support/oauth_stub_server.dart';
import '../support/temp_directory.dart';

/// End-to-end proof for oauth-admin-add's premise: `zonai db admin add`
/// (`ZonaiDb.createAdmin`) can create a row on an `AsAdmin` table that mixes
/// in `OAuth` but NOT `PasswordAuth`, and that row is then reachable by a
/// real OAuth sign-in -- the linking half `oauth_e2e_test.dart` already
/// covers, exercised here specifically without a password ever existing.
///
/// A dedicated fixture (`e2e/oauth_admin_add`, single `admins` table) rather
/// than a second table bolted onto `e2e/oauth`'s `users`: `ZonaiDb.adminTable`
/// resolves "the" admin table as the first `AsAdmin` table the compiled
/// project registers, so two admin tables in one project would make which
/// one `admin add` targets a function of schema-file iteration order rather
/// than a documented contract -- exactly the ambiguity `e2e/oauth`'s single
/// `users` table (`PasswordAuth, OAuth, AsAdmin`) sidesteps for the
/// "password path unchanged" side. Keeping one admin table per fixture
/// keeps both sides unambiguous.
void main() {
  group('oauth admin add e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;
    late AppConfig appConfig;
    late OAuthStubServer stub;

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      stub = await OAuthStubServer.start();

      fixtureRoot = Directory(
        p.normalize(
          p.join(Directory.current.path, '..', '..', 'e2e', 'oauth_admin_add'),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/oauth_admin_add'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_oauth_admin_add_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(projectRoot: projectRoot, repoRoot: repoRoot);
      _rewriteStubBaseUrl(projectRoot: projectRoot, baseUrl: stub.baseUrl);

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
      ], workingDirectory: projectRoot.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}\n${pubGet.stdout}');

      settings = await runMergedScopedFuture(
        () async => Settings.load(projectRoot.path),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );
      appConfig = AppConfig(
        appName: 'OAuth Admin Add E2E',
        passwordSecret: 'e2e-password-pepper',
        jwtSecret: 'e2e-zonai-jwt-secret',
        baseUrl: 'http://localhost:8080',
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
    });

    tearDownAll(() async {
      if (!_runningOnDartVm) {
        return;
      }
      await stub.close();
      deleteTempDirectory(projectRoot);
    });

    Future<T> withDb<T>(Future<T> Function(ZonaiDb db) body) {
      return runMergedScopedFuture(() async {
        final db = ZonaiDb();
        try {
          return await body(db);
        } finally {
          await db.dispose();
        }
      }, override: _e2eScopeOverrides(settings, appConfig: appConfig));
    }

    test('adminTable resolves the OAuth-only admins table, with no password '
        'in its supported auth types', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final (table, authTypes) = await db.adminTable();
        expect(table, 'admins');
        expect(authTypes, contains(AuthType.oauth));
        expect(authTypes, isNot(contains(AuthType.password)));
      });
    });

    test('createAdmin rejects a supplied password on an OAuth-only admin '
        'table', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        // `ZonaiDb._run`'s catch-all normalizes any exception outside its
        // whitelist (AuthException/CrudException/...) into a wrapping
        // `StateError` -- the same thing that already happens to the
        // pre-existing "account already exists" `StateError` in
        // `_createAdmin`, so this asserts the same way that one would.
        await expectLater(
          db.createAdmin(
            email: 'rejected-${clock.now().microsecondsSinceEpoch}@example.com',
            password: 'should-not-be-allowed',
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    test('an OAuth-only admin table refuses direct invite acceptance of a '
        'LIVE invite, and names the route that works', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        // Design §3.3's boundary. Direct acceptance is authorized by the
        // invite token alone; §3.2's OAuth path additionally has a provider
        // vouch that the identity signing in owns the invited address. A
        // table offering nothing but OAuth has chosen the stronger claim, so
        // the weaker door is refused rather than quietly opened.
        //
        // The invite has to be REAL for this to prove anything: an unknown
        // token is refused as unknown, several checks earlier, and a test
        // written that way would still pass with the OAuth-only check
        // deleted. `inviteAdminFromCli` is what makes a live one reachable
        // here -- there is no admin session on this fixture to issue one
        // with, which is the same bootstrap problem it exists to solve.
        final email =
            'invited-${clock.now().microsecondsSinceEpoch}@example.com';
        await db.inviteAdminFromCli(email: email);

        // Live, and it is this table's.
        final described = await db.describeAdminInvite(
          token: 'dev-admin-invite',
        );
        expect(described, isNotNull);
        expect(described!.authTypes, [AuthType.oauth]);

        await expectLater(
          db.acceptAdminInvite(token: 'dev-admin-invite', password: 'pw'),
          throwsA(isA<AdminInviteRequiresOAuthException>()),
        );

        // Refused before anything was created, and -- the part that would
        // hurt most to get wrong -- before the invite was spent. The invitee
        // must still be able to accept it the way this table intends.
        expect(
          (await db.listAdmins()).where((a) => a['email'] == email),
          isEmpty,
        );
        expect(
          await db.describeAdminInvite(token: 'dev-admin-invite'),
          isNotNull,
          reason: 'a refused direct acceptance must leave the OAuth path open',
        );
      });
    });

    test('createAdmin with no password creates a verified, password-less row '
        'that a subsequent OAuth sign-in with the same verified email links '
        'to and signs in', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final email = 'ceo-${clock.now().microsecondsSinceEpoch}@example.com';

        final created = await db.createAdmin(email: email, password: null);

        expect(created['email'], email);
        expect(created['is_verified'], _truthy);
        expect(created.containsKey('password'), isFalse);

        final url = await db.startAdminOAuth(
          const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final state = Uri.parse(url).queryParameters['state']!;
        final code = OAuthStubServer.code(
          sub: 'admin-first-google-signin',
          email: email,
          emailVerified: true,
        );

        final result = await db.completeOAuth(
          CompleteOAuthAuthPayload(state: state, code: code),
        );

        expect(result.user['email'], email);
        expect(result.user['id'], created['id']);
        expect(result.jwt, isNotEmpty);

        // Linked via step 2 (email match), not provisioned: still exactly
        // one row for this email.
        final rows = await db.list('admins', ListPayload(where: null));
        expect(rows.items.where((r) => r['email'] == email), hasLength(1));
      });
    });

    test('createAdmin with --no-verify (verified: false) leaves the row '
        'unverified', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final email =
            'unverified-${clock.now().microsecondsSinceEpoch}@example.com';

        final created = await db.createAdmin(
          email: email,
          password: null,
          verified: false,
        );

        expect(created['is_verified'], isNot(_truthy));
      });
    });
  });
}

/// Matches a boolean column's wire value, whether the driver reports it as
/// `true`/`false` or `1`/`0`.
final Matcher _truthy = predicate<Object?>(
  (value) => value == true || value == 1,
  'truthy',
);

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

Set<ScopedRef<dynamic>> _e2eScopeOverrides(
  Settings settings, {
  AppConfig? appConfig,
}) {
  return {
    fsProvider.overrideWith(LocalFileSystem.new),
    loggerProvider.overrideWith(() => Logger(level: .error)),
    settingsProvider.overrideWith(() => settings),
    processProvider,
    migrateProvider,
    mutationsProvider,
    cleanUpProvider,
    executableStopProvider,
    // Needed since this file exercises `inviteAdminFromCli`, which mails the
    // invite. No email is configured on this fixture, so `Courier._send`
    // returns early and the call is a silent no-op -- but the provider still
    // has to be in scope to be read.
    courierProvider,
    if (appConfig != null)
      configResolverProvider.overrideWith(
        () => ConfigResolver.fixed(appConfig),
      ),
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

/// The fixture project only depends on `zonai_schema`, not `zonai` itself,
/// so it can't JIT-link a project-linked entry (`package:zonai/...` isn't
/// resolvable from it). Forcing Mailman/IPC workers skips that project-linked
/// re-exec (see `maybeReexecProjectRuntime`) and drives `db migrate
/// generate`/`apply` through the already-compiled worker executables instead.
const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_oauth_admin_add_e2e
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaRoot)}
''');
}

/// The stub server's port is only known once it has bound (after this
/// project is copied into a temp dir), so the schema's placeholder base URL
/// is filled in here rather than baked into the checked-in fixture.
void _rewriteStubBaseUrl({
  required Directory projectRoot,
  required String baseUrl,
}) {
  final adminsSchema = File(
    p.join(projectRoot.path, 'lib', 'src', 'schemas', 'admins.dart'),
  );
  final rewritten = adminsSchema.readAsStringSync().replaceAll(
    '__OAUTH_STUB_BASE_URL__',
    baseUrl,
  );
  expect(
    rewritten,
    isNot(contains('__OAUTH_STUB_BASE_URL__')),
    reason: 'stub base URL placeholder was not found in admins.dart',
  );
  adminsSchema.writeAsStringSync(rewritten);
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
