import 'dart:convert';
import 'dart:io';

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
import '../support/temp_directory.dart';

/// Checks a field report: "`PATCH /db` 500s on any `where` that isn't on `id`,
/// while `list` accepts the same clause happily."
///
/// `PATCH /db` returns a single row, and `DbHandler.update`
/// (apps/server/lib/src/handlers/db_handler.dart) turns an empty result into
/// `StateError('Update did not return a row')` — a 500. So at this layer the
/// question is whether [ZonaiDb.update] comes back **empty**; that empty list
/// is the 500.
///
/// Three cases, because "non-id" and "a column the update also writes" are
/// different properties that the reported call sites happened to share:
///
///  - [_matchNonIdUntouched] — non-id `where`, column NOT written.
///  - [_matchNonIdRewritten] — non-id `where`, column written by the same
///    update. `_update` used to refetch by replaying the *pre-update* `where`,
///    so the row it had just rewritten could no longer match: the write
///    committed and the caller still got a failure. It now reads back by the
///    ids captured before the write (`_refetchOperation`).
///  - [_matchById] — the control the report says works.
void main() {
  group('update where-column e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;
    late AppConfig appConfig;

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      fixtureRoot = Directory(
        p.normalize(
          p.join(
            Directory.current.path,
            '..',
            '..',
            'e2e',
            'admin_password_update_repro',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/admin_password_update_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_update_where_column_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(projectRoot: projectRoot, repoRoot: repoRoot);

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
        appName: 'Update Where Column E2E',
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

    tearDownAll(() {
      deleteTempDirectory(projectRoot);
    });

    Future<void> withDb(Future<void> Function(ZonaiDb db) body) async {
      late ZonaiDb db;
      await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            await body(db);
          } finally {
            await db.dispose();
          }
        },
        override: {
          ..._e2eScopeOverrides(settings, appConfig: appConfig),
          zonaiDbProvider.overrideWith(
            () =>
                () => db,
          ),
        },
      );
    }

    /// The fixture's `users` rules deny `update` to a plain user token; the
    /// admin e2e test uses an admin for the same reason. This is about the
    /// where clause, not authorization, so every case runs as admin.
    Future<String> adminToken(ZonaiDb db, String email) async {
      final signUp = await db.authenticate(
        'admins',
        PasswordAuthPayload(email: email, password: 'admin-password-1'),
      );
      expect(signUp, isNotNull);
      return signUp!.jwt;
    }

    test(_matchNonIdUntouched, () async {
      if (!_runningOnDartVm) {
        return;
      }

      await withDb((db) async {
        const email = 'untouched@example.com';
        final signUp = await db.authenticate(
          'users',
          const PasswordAuthPayload(email: email, password: 'password-1'),
        );
        expect(signUp, isNotNull);
        final token = await adminToken(db, 'admin-untouched@example.com');

        // The read half the report says works.
        final listed = await db.list(
          'users',
          ListPayload(where: const Eq('email', email), jwt: token),
        );
        expect(
          listed.items,
          hasLength(1),
          reason: 'list must accept a non-id where',
        );

        final updated = await db.update(
          'users',
          UpdatePayload(
            where: const Eq('email', email),
            updates: [
              Update.object({'is_verified': true}),
            ],
            jwt: token,
          ),
        );

        expect(
          updated,
          hasLength(1),
          reason:
              'a non-id where that the update does not write must return the '
              'row; an empty result is the 500 PATCH /db reports',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(_matchNonIdRewritten, () async {
      if (!_runningOnDartVm) {
        return;
      }

      await withDb((db) async {
        const email = 'rewritten@example.com';
        const newEmail = 'rewritten-new@example.com';
        final signUp = await db.authenticate(
          'users',
          const PasswordAuthPayload(email: email, password: 'password-2'),
        );
        expect(signUp, isNotNull);
        final token = await adminToken(db, 'admin-rewritten@example.com');

        Object? thrown;
        List<Map<String, Object?>>? updated;
        try {
          updated = await db.update(
            'users',
            UpdatePayload(
              where: const Eq('email', email),
              updates: [
                Update.object({'email': newEmail}),
              ],
              jwt: token,
            ),
          );
        } catch (e) {
          thrown = e;
        }

        // The write lands either way -- this is what makes the failure
        // dangerous rather than merely noisy: the caller sees a 500 and the
        // row is already changed, so a retry matches nothing.
        final after = await db.list(
          'users',
          ListPayload(where: const Eq('email', newEmail), jwt: token),
        );
        expect(
          after.items,
          hasLength(1),
          reason: 'the update was written despite the failure',
        );

        expect(
          thrown,
          isNull,
          reason:
              'refetching with the pre-update where cannot match the row it '
              'just rewrote: with asserts on (dart test) that trips the '
              'before/after length assert in AfterUpdateExtensionRequest; in '
              'a compiled binary the empty result reaches DbHandler.update '
              'and 500s there instead',
        );
        expect(updated, hasLength(1));
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(_matchNoRows, () async {
      if (!_runningOnDartVm) {
        return;
      }

      await withDb((db) async {
        final token = await adminToken(db, 'admin-no-rows@example.com');

        final updated = await db.update(
          'users',
          UpdatePayload(
            where: const Eq('email', 'nobody-has-this@example.com'),
            updates: [
              Update.object({'is_verified': true}),
            ],
            jwt: token,
          ),
        );

        // Zero rows is a legitimate outcome of a conditional update ("close it
        // if it is still open"). `DbHandler.update` turns this empty result
        // into `RecordNotFoundException` -> 404; it used to be a `StateError`
        // -> 500, which a caller could not tell from a server fault.
        expect(
          updated,
          isEmpty,
          reason: 'a where matching nothing updates nothing',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(_matchById, () async {
      if (!_runningOnDartVm) {
        return;
      }

      await withDb((db) async {
        const email = 'by-id@example.com';
        final signUp = await db.authenticate(
          'users',
          const PasswordAuthPayload(email: email, password: 'password-3'),
        );
        expect(signUp, isNotNull);
        final id = signUp!.user['id'];
        final token = await adminToken(db, 'admin-by-id@example.com');
        expect(id, isNotNull);

        final updated = await db.update(
          'users',
          UpdatePayload(
            where: Eq('id', id!),
            updates: [
              Update.object({'is_verified': true}),
            ],
            jwt: token,
          ),
        );

        expect(
          updated,
          hasLength(1),
          reason: 'the control the report says works',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

const _matchNonIdUntouched =
    'a non-id where whose column the update does not write returns the row';
const _matchNonIdRewritten =
    'a where on a column the same update rewrites still returns the row';
const _matchNoRows =
    'a where matching no rows returns empty (PATCH /db turns that into a 404)';
const _matchById = 'a where on id returns the row';

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

/// See the note in `admin_password_update_e2e_test.dart`: the fixture depends
/// only on `zonai_schema`, so it cannot JIT-link a project-linked entry.
const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_admin_password_update_repro
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
