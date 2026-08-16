import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';
import 'package:zonai_server/src/handlers/maintenance_handler.dart';

/// Every maintenance verb is admin-only, and refuses *before* it acts.
///
/// These are the destructive endpoints: they delete rows and rewrite database
/// files. So the property worth pinning is not just that a non-admin gets an
/// error back, but that the engine was never reached — an endpoint that
/// emptied `_log` and *then* threw would pass a test that only checked the
/// exception.
///
/// Structured as a table over the verbs rather than four hand-written groups,
/// so a fifth verb added without a gate is a missing row here rather than a
/// silently untested endpoint.
void main() {
  Jwt jwtWith({required bool isAdmin}) => Jwt(
    userId: UnknownId('u'),
    table: '_user',
    jwtId: JwtId('j'),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const {},
    claims: const {},
    admin: (isAdmin: isAdmin, canEdit: isAdmin ? true : null),
  );

  /// One endpoint, named, and the call that exercises it.
  final verbs = <String, Future<void> Function(String? authorization)>{
    'purgeLogs': (auth) => const MaintenanceHandler().purgeLogs(
      auth,
      body: const PurgeLogsBody(olderThanDays: 30),
    ),
    'purgeTable': (auth) => const MaintenanceHandler().purgeTable(
      auth,
      body: const PurgeTableBody(table: '_log'),
    ),
    'cleanupPhotos': (auth) => const MaintenanceHandler().cleanupPhotos(auth),
    'reclaimLogSpace': (auth) =>
        const MaintenanceHandler().reclaimLogSpace(auth),
  };

  /// The three ways a caller can fail to be an admin.
  final rejectedCallers = <String, ({Jwt? jwt, String? authorization})>{
    'a signed-in caller who is not an admin': (
      jwt: jwtWith(isAdmin: false),
      authorization: 'Bearer some-token',
    ),
    'a caller with no Authorization header at all': (
      jwt: null,
      authorization: null,
    ),
    // `parseJwt` answers null for a token it cannot verify, which has to read
    // as "not an admin" rather than falling through.
    'a token that does not parse': (jwt: null, authorization: 'Bearer garbage'),
  };

  for (final MapEntry(key: verb, value: call) in verbs.entries) {
    group(verb, () {
      for (final MapEntry(key: who, value: caller) in rejectedCallers.entries) {
        test('refuses $who', () async {
          final db = _StubZonaiDb(jwt: caller.jwt);

          await runScoped(() async {
            await expectLater(
              call(caller.authorization),
              throwsA(isA<TableAccessDeniedException>()),
            );
            expect(
              db.acted,
              isEmpty,
              reason:
                  'the refusal has to come before the work -- these verbs '
                  'delete rows and rewrite database files, so an endpoint '
                  'that acted and then threw would still have done the '
                  'damage. Reached: ${db.acted}',
            );
          }, values: {zonaiDbProvider.overrideWith(() => () => db)});
        });
      }

      test('lets an admin through to the engine', () async {
        final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

        await runScoped(() async {
          await call('Bearer admin-token');
          expect(
            db.acted,
            isNotEmpty,
            reason:
                'a gate that refuses everyone would pass the tests above for '
                'the wrong reason',
          );
        }, values: {zonaiDbProvider.overrideWith(() => () => db)});
      });
    });
  }

  group('purgeTable table gate', () {
    test('refuses _photos before reaching the engine', () async {
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await runScoped(() async {
        await expectLater(
          const MaintenanceHandler().purgeTable(
            'Bearer admin-token',
            body: const PurgeTableBody(table: '_photos'),
          ),
          throwsA(isA<TableAccessDeniedException>()),
        );
        expect(
          db.acted,
          isEmpty,
          reason:
              'a bulk DELETE on _photos removes rows without running the '
              'per-row path that deletes the file behind each one, orphaning '
              'every file it removed a row for. Admin is not enough here.',
        );
      }, values: {zonaiDbProvider.overrideWith(() => () => db)});
    });

    test('refuses an application table', () async {
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await runScoped(() async {
        await expectLater(
          const MaintenanceHandler().purgeTable(
            'Bearer admin-token',
            body: const PurgeTableBody(table: 'users'),
          ),
          throwsA(isA<TableAccessDeniedException>()),
        );
        expect(db.acted, isEmpty);
      }, values: {zonaiDbProvider.overrideWith(() => () => db)});
    });

    test('passes a purgeable table through with a match-all predicate', () async {
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await runScoped(() async {
        final result = await const MaintenanceHandler().purgeTable(
          'Bearer admin-token',
          body: const PurgeTableBody(table: '_jwt'),
        );

        expect(result.rowsAffected, 7);
        expect(db.purgedTable, '_jwt');
        // Every internal table has an `id` primary key; `rowid` is in no
        // generated schema and the operations layer would reject it.
        expect(db.purgedWhere, isA<NotNull>());
        expect((db.purgedWhere! as NotNull).column, 'id');
      }, values: {zonaiDbProvider.overrideWith(() => () => db)});
    });
  });

  group('purgeLogs cutoff', () {
    test('a null olderThanDays means every row', () async {
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await runScoped(() async {
        await const MaintenanceHandler().purgeLogs(
          'Bearer admin-token',
          body: const PurgeLogsBody(),
        );
        expect(db.clearLogsBefore, isNull);
      }, values: {zonaiDbProvider.overrideWith(() => () => db)});
    });

    test('a day count becomes a server-side cutoff', () async {
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await runScoped(() async {
        final now = DateTime.now();
        await const MaintenanceHandler().purgeLogs(
          'Bearer admin-token',
          body: const PurgeLogsBody(olderThanDays: 30),
        );

        final before = db.clearLogsBefore;
        expect(before, isNotNull);
        // Computed from the server's clock, not sent by the browser: a client
        // running a day fast would otherwise delete a day more than asked.
        //
        // Bounded rather than exact. The handler reads its own clock a moment
        // *after* `now` above, so the cutoff it computes sits a hair later
        // than `now - 30d` and this gap is a few microseconds under 30 days --
        // which `inDays` truncates to 29.
        final age = now.difference(before!);
        expect(age, lessThanOrEqualTo(const Duration(days: 30)));
        expect(age, greaterThan(const Duration(days: 29, hours: 23)));
      }, values: {zonaiDbProvider.overrideWith(() => () => db)});
    });

    test('a negative day count is refused', () async {
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await runScoped(() async {
        await expectLater(
          const MaintenanceHandler().purgeLogs(
            'Bearer admin-token',
            body: const PurgeLogsBody(olderThanDays: -1),
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          db.acted,
          isEmpty,
          reason:
              'a negative cutoff is a future timestamp, which matches every '
              'row -- "purge the last -1 days" must not mean "purge all"',
        );
      }, values: {zonaiDbProvider.overrideWith(() => () => db)});
    });
  });

  group('reclaimLogSpace result', () {
    test('passes the skip reason through verbatim', () async {
      final db = _StubZonaiDb(
        jwt: jwtWith(isAdmin: true),
        reclamation: (
          reclaimableBytes: 32 * 1024 * 1024,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: 'not enough free disk for the rewrite',
        ),
      );

      await runScoped(() async {
        final result = await const MaintenanceHandler().reclaimLogSpace(
          'Bearer admin-token',
        );

        // The whole reason this payload carries a string rather than a bool:
        // a full volume reclaims nothing, and without the reason that is
        // indistinguishable from having had nothing to reclaim.
        expect(result.skipped, 'not enough free disk for the rewrite');
        expect(result.vacuumed, isFalse);
        expect(result.reclaimedBytes, 0);
        expect(result.reclaimableBytes, 32 * 1024 * 1024);
      }, values: {zonaiDbProvider.overrideWith(() => () => db)});
    });

    test('a successful rewrite carries no skip reason', () async {
      final db = _StubZonaiDb(
        jwt: jwtWith(isAdmin: true),
        reclamation: (
          reclaimableBytes: 32 * 1024 * 1024,
          reclaimedBytes: 30 * 1024 * 1024,
          vacuumed: true,
          skipped: null,
        ),
      );

      await runScoped(() async {
        final result = await const MaintenanceHandler().reclaimLogSpace(
          'Bearer admin-token',
        );
        expect(result.skipped, isNull);
        expect(result.vacuumed, isTrue);
        expect(result.reclaimedBytes, 30 * 1024 * 1024);
      }, values: {zonaiDbProvider.overrideWith(() => () => db)});
    });
  });
}

/// A [ZonaiDb] that answers a fixed [Jwt] and records which verbs were reached.
///
/// [acted] is the load-bearing field: the gate's job is to keep it empty for
/// an unauthorized caller.
class _StubZonaiDb implements ZonaiDb {
  _StubZonaiDb({required this.jwt, this.reclamation});

  final Jwt? jwt;
  final LogSpaceReclamation? reclamation;

  final List<String> acted = [];
  DateTime? clearLogsBefore;
  String? purgedTable;
  Where? purgedWhere;

  @override
  Future<Jwt?> parseJwt(String? token) async => jwt;

  @override
  Future<int> clearLogs({DateTime? before}) async {
    acted.add('clearLogs');
    clearLogsBefore = before;
    return 3;
  }

  @override
  Future<int> purge({
    required String table,
    required Where where,
    required Jwt? jwt,
  }) async {
    acted.add('purge');
    purgedTable = table;
    purgedWhere = where;
    return 7;
  }

  @override
  Future<int> cleanupUnreferencedPhotos() async {
    acted.add('cleanupUnreferencedPhotos');
    return 2;
  }

  @override
  Future<LogSpaceReclamation> reclaimLogSpace() async {
    acted.add('reclaimLogSpace');
    return reclamation ??
        (
          reclaimableBytes: 0,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: null,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
