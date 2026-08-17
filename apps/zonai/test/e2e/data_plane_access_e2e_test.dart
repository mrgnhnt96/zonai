import 'dart:async';
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

/// The data-plane access-control findings from the 2026-08 pen-test, each
/// driven through a real `ZonaiDb` against a real database.
///
/// These are end-to-end on purpose. Every one of them is a disagreement
/// *between* layers — what the rules were asked versus what the SQL then did,
/// or what the sanitizer strips versus what the response carried — and a unit
/// test on either side alone reports that both halves are fine.
///
/// The fixture (`e2e/data_plane_access_repro`) carries two shapes:
///  - `users`/`admins`: auth collections with a `PasswordColumn`, for the
///    secret-column findings. `admins` is `AsAdmin`, so its token is the
///    "authorized reader" whose `GET /db/list` returned an Argon2 hash.
///  - `notes`: permissive table rules, restrictive row rules — the arrangement
///    the SSE stream leak depended on.
void main() {
  group('data-plane access control e2e', () {
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
            'data_plane_access_repro',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/data_plane_access_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_data_plane_access_e2e_');
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
        appName: 'Data Plane Access E2E',
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

    /// An admin token — `admins` is `AsAdmin`, so this is `isAdmin`/`canEdit`,
    /// the most privileged reader the data plane recognises.
    Future<String> adminToken(ZonaiDb db, String email) async {
      final signUp = await db.authenticate(
        'admins',
        PasswordAuthPayload(email: email, password: 'admin-password-1'),
      );
      expect(signUp, isNotNull);
      return signUp!.jwt;
    }

    Future<({String jwt, String id})> user(ZonaiDb db, String email) async {
      final signUp = await db.authenticate(
        'users',
        PasswordAuthPayload(email: email, password: 'user-password-1'),
      );
      expect(signUp, isNotNull);
      final id = signUp!.user['id'];
      expect(id, isNotNull);
      return (jwt: signUp.jwt, id: '$id');
    }

    test(_f2List, () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        await user(db, 'f2-list@example.com');
        final token = await adminToken(db, 'admin-f2-list@example.com');

        final listed = await db.list(
          'users',
          ListPayload(
            where: const Eq('email', 'f2-list@example.com'),
            jwt: token,
          ),
        );

        expect(listed.items, hasLength(1));
        // The live finding: this key was present, holding the Argon2 hash,
        // because `_sanitizeRows` exempted an admin token from stripping it.
        expect(
          listed.items.single.containsKey('password'),
          isFalse,
          reason:
              'a password hash must not be serialized to any client, admin '
              'included: it is an offline cracking target for a password the '
              'user has probably reused elsewhere',
        );
        expect(listed.items.single['email'], 'f2-list@example.com');
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(_f2Patch, () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        await user(db, 'f2-patch@example.com');
        final token = await adminToken(db, 'admin-f2-patch@example.com');

        final updated = await db.update(
          'users',
          UpdatePayload(
            where: const Eq('email', 'f2-patch@example.com'),
            updates: [
              Update.object({'is_verified': true}),
            ],
            jwt: token,
          ),
        );

        expect(updated, hasLength(1));
        // The PATCH response echoed the hash by the same route as the list.
        expect(updated.single.containsKey('password'), isFalse);
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(_g4Oracle, () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        await user(db, 'g4@example.com');
        final token = await adminToken(db, 'admin-g4@example.com');

        // Stripping the column from the response is not enough while it stays
        // filterable: this is a blind prefix oracle over the hash, answered by
        // the row count rather than the body.
        await expectLater(
          db.list(
            'users',
            ListPayload(
              where: const StartsWith('password', r'$argon2'),
              jwt: token,
            ),
          ),
          throwsA(isA<SecretColumnFilterException>()),
        );

        await expectLater(
          db.count(
            'users',
            CountPayload(
              where: const StartsWith('password', r'$argon2'),
              jwt: token,
            ),
          ),
          throwsA(isA<SecretColumnFilterException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(_g7UnknownColumn, () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final token = await adminToken(db, 'admin-g7@example.com');

        // Previously interpolated into the statement and 500ed from SQLite.
        await expectLater(
          db.list(
            'users',
            ListPayload(where: const Eq('no_such_column', 'x'), jwt: token),
          ),
          throwsA(isA<ColumnNotFoundException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(_g2Update, () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final owner = await user(db, 'g2-update-owner@example.com');
        final token = await adminToken(db, 'admin-g2-update@example.com');

        for (final title in const ['one', 'two', 'three']) {
          await db.create(
            'notes',
            CreatePayload(
              object: {'title': title, 'owner_id': owner.id},
              jwt: token,
            ),
          );
        }

        // `UpdateOne` reads with LIMIT 1 -- one row is adjudicated -- and the
        // UPDATE it built carried no limit at all, so all three were written.
        final updated = await db.update(
          'notes',
          UpdatePayload(
            where: Eq('owner_id', owner.id),
            limit: 1,
            updates: [
              Update.object({'title': 'rewritten'}),
            ],
            jwt: token,
          ),
        );

        expect(updated, hasLength(1), reason: 'one row authorized');

        final rewritten = await db.list(
          'notes',
          ListPayload(where: const Eq('title', 'rewritten'), jwt: owner.jwt),
        );
        expect(
          rewritten.items,
          hasLength(1),
          reason:
              'exactly one row may be written: the update is now keyed to the '
              'ids the rules gate admitted, not replayed from the where',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(_g2Delete, () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final owner = await user(db, 'g2-delete-owner@example.com');
        final token = await adminToken(db, 'admin-g2-delete@example.com');

        final ids = <String>[];
        for (final title in const ['oldest', 'middle', 'newest']) {
          final created = await db.create(
            'notes',
            CreatePayload(
              object: {'title': title, 'owner_id': owner.id},
              jwt: token,
            ),
          );
          ids.add('${created['id']}');
          // created_at is the default sort key; distinct timestamps keep
          // "newest" unambiguous.
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }

        final deleted = await db.delete(
          'notes',
          DeletePayload(where: Eq('owner_id', owner.id), limit: 1, jwt: token),
        );
        expect(deleted, 1, reason: 'exactly one row removed');

        final remaining = await db.list(
          'notes',
          ListPayload(where: Eq('owner_id', owner.id), jwt: owner.jwt),
        );
        final titles = remaining.items.map((e) => e['title']).toList();

        // The pre-read that authorized the delete orders by created_at DESC
        // and takes one -- "newest". The delete's own LIMIT subquery had no
        // ORDER BY, so it removed whichever row SQLite reached first, which
        // live was the oldest. The row checked and the row removed must match.
        expect(
          titles,
          unorderedEquals(<String>['oldest', 'middle']),
          reason:
              'the row the rules authorized (newest) is the row that was '
              'deleted',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(_g1Stream, () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final owner = await user(db, 'g1-owner@example.com');
        final token = await adminToken(db, 'admin-g1@example.com');

        // An anonymous subscription. `notes` table rules allow `list`, so the
        // stream opens; the row rule allows nothing to an anon caller.
        final anonSeen = <Map<String, Object?>>[];
        final anonSub = db
            .streamList(
              'notes',
              ListPayload(where: const Eq('title', 'secret')),
            )
            .listen(anonSeen.addAll, onError: (Object _) {});

        // And the owner's subscription, as the positive control: the fix must
        // filter denied rows, not break streaming.
        final ownerSeen = <Map<String, Object?>>[];
        final ownerSub = db
            .streamList(
              'notes',
              ListPayload(where: const Eq('title', 'secret'), jwt: owner.jwt),
            )
            .listen(ownerSeen.addAll, onError: (Object _) {});

        // Let both snapshots settle. Both are empty -- which is precisely the
        // hole: `_requireRowsAccess` returns early on an empty list, so the
        // anon subscription was authorized by a check that ran over no rows.
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(anonSeen, isEmpty);
        expect(ownerSeen, isEmpty);

        await db.create(
          'notes',
          CreatePayload(
            object: {'title': 'secret', 'owner_id': owner.id},
            jwt: token,
          ),
        );

        await Future<void>.delayed(const Duration(seconds: 2));

        // Deliberately not awaited. `HybridStreamEngine._subscribe` closes the
        // controller from inside its own `onCancel`, and awaiting the returned
        // future here never completes -- a pre-existing stream-lifecycle bug,
        // unrelated to access control and outside this fixture's subject.
        // `db.dispose()` in `withDb` tears the delegate down regardless.
        unawaited(anonSub.cancel());
        unawaited(ownerSub.cancel());

        expect(
          anonSeen,
          isEmpty,
          reason:
              'a row pushed after the stream opened must be re-checked: the '
              'anon caller fails the row rule and must never receive it',
        );
        expect(
          ownerSeen.map((e) => e['title']),
          contains('secret'),
          reason:
              'the owner passes the row rule and must still be pushed the '
              'row -- denied rows are filtered, the stream is not broken',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

const _f2List =
    'GET /db/list never serializes a password column, not even to '
    'an admin (F-2)';
const _f2Patch = 'the PATCH /db response never echoes a password column (F-2)';
const _g4Oracle =
    'a where on a secret column is refused, closing the prefix oracle (G-4)';
const _g7UnknownColumn =
    'a where on an unregistered column is a 400, not a 500 (G-7)';
const _g2Update = 'an update writes only the rows its rules authorized (G-2)';
const _g2Delete =
    'a limited delete removes the row it authorized, not another (G-2)';
const _g1Stream =
    'a stream re-checks row access on every emission, not just the initial '
    'snapshot (G-1)';

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
name: zonai_data_plane_access_repro
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
