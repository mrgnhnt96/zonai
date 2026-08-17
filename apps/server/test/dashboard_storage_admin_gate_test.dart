import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';
import 'package:zonai_server/src/handlers/dashboard_handler.dart';

/// `GET dashboard/storage` is admin-only, and refuses *before* it collects.
///
/// The report names every database path on the host, the size of each file,
/// and the row count of every internal table — operator information, not
/// tenant information. The engine refuses a non-admin too, so this is the
/// outer of two locks rather than the only one; what this pins is that the
/// outer lock exists and is the same shape as the one on
/// [DashboardHandler.metrics].
///
/// Refusing before collecting also matters on its own: collection shells out
/// to `df` and walks the photos directory, so an unauthenticated caller who
/// got as far as the work would be a way to make the server do it on demand.
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

  Future<void> expectRefused(_StubZonaiDb db, String? authorization) async {
    await runScoped(
      () async {
        await expectLater(
          const DashboardHandler().storage(authorization),
          throwsA(isA<TableAccessDeniedException>()),
        );
        expect(
          db.collected,
          isFalse,
          reason:
              'the refusal has to come before the collection -- `df` and a '
              'recursive directory walk are not work an unauthorized caller '
              'should be able to ask for',
        );
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
  }

  test('refuses a signed-in caller who is not an admin', () async {
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: false));
    await expectRefused(db, 'Bearer some-token');
  });

  test('refuses a caller with no Authorization header at all', () async {
    final db = _StubZonaiDb(jwt: null);
    await expectRefused(db, null);
  });

  test('refuses a token that does not parse', () async {
    // `parseJwt` answers null for a token it cannot verify, which has to read
    // as "not an admin" rather than falling through.
    final db = _StubZonaiDb(jwt: null);
    await expectRefused(db, 'Bearer garbage');
  });

  test('lets an admin through to the collection', () async {
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    await runScoped(
      () async {
        await const DashboardHandler().storage('Bearer admin-token');
        expect(
          db.collected,
          isTrue,
          reason:
              'a gate that refuses everyone would pass the tests above for '
              'the wrong reason',
        );
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
  });
}

/// A [ZonaiDb] that answers a fixed [Jwt] and records whether the storage
/// collection was ever reached.
class _StubZonaiDb implements ZonaiDb {
  _StubZonaiDb({required this.jwt});

  final Jwt? jwt;
  bool collected = false;

  @override
  Future<Jwt?> parseJwt(String? token) async => jwt;

  @override
  Future<StorageMetrics> storageMetrics({required Jwt jwt}) async {
    collected = true;
    return const StorageMetrics(
      databases: [],
      photosBytes: 0,
      photosFileCount: 0,
      tables: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
