import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart';
import 'package:zonai_schema/src/types/supported_auths.dart' show AuthType;
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';
import 'package:zonai_server/src/handlers/admin_handler.dart';

/// The three `require-password-reset` routes are admin-only, and refuse BEFORE
/// they write.
///
/// "Before it writes" is the property, and it is not the same as "returns an
/// error". Setting a requirement REVOKES every session the account holds, so a
/// handler that acted and then threw would have signed a user out of every
/// device on behalf of a caller who was never authorized — and the refusal the
/// caller saw would look like nothing had happened. So the assertion is on the
/// runtime having been left untouched.
///
/// The other property under test is the one that makes these routes different
/// from every neighbour in `AdminController`: they take `table`, and act on
/// THAT rather than on the resolved `AsAdmin` collection. The row detail panel
/// offers this on any collection with a password column, so a handler that
/// resolved the admin table would look a `users` address up in `admins` and
/// find nothing, while telling the operator it worked.
void main() {
  Jwt jwtWith({required bool isAdmin, String table = 'admins'}) => Jwt(
    userId: UnknownId('acting-admin'),
    table: table,
    jwtId: JwtId('j'),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const {},
    claims: const {},
    admin: (isAdmin: isAdmin, canEdit: isAdmin ? true : null),
  );

  final rejectedCallers = <String, ({Jwt? jwt, String? authorization})>{
    'a signed-in caller who is not an admin': (
      jwt: jwtWith(isAdmin: false),
      authorization: 'Bearer some-token',
    ),
    'a caller with no Authorization header at all': (
      jwt: null,
      authorization: null,
    ),
    'a token that does not parse': (jwt: null, authorization: 'Bearer garbage'),
    // `jwt.admin.isAdmin` is scoped to the JWT's own collection. In a project
    // with two `AsAdmin` tables, an admin for the second must not be able to
    // lock accounts out of the first. Same clause `_requireAdmin`'s doc calls
    // "the one that is easy to drop".
    'an admin for a DIFFERENT admin table': (
      jwt: jwtWith(isAdmin: true, table: 'other_admins'),
      authorization: 'Bearer other-admin-token',
    ),
  };

  Future<void> withDb(_StubZonaiDb db, Future<void> Function() body) {
    return runScoped(
      body,
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
  }

  for (final MapEntry(key: who, value: caller) in rejectedCallers.entries) {
    test('requirePasswordReset refuses $who', () async {
      final db = _StubZonaiDb(jwt: caller.jwt);

      await withDb(db, () async {
        await expectLater(
          const AdminHandler().requirePasswordReset(
            authorization: caller.authorization,
            email: 'a@example.com',
            table: 'users',
          ),
          throwsA(isA<TableAccessDeniedException>()),
        );
        expect(
          db.acted,
          isEmpty,
          reason:
              'the refusal has to come before the write -- setting a '
              'requirement revokes every session the account holds, so a '
              'handler that acted and then threw would have signed a user out '
              'of every device for an unauthorized caller. Reached: ${db.acted}',
        );
      });
    });

    test('clearPasswordReset refuses $who', () async {
      final db = _StubZonaiDb(jwt: caller.jwt);

      await withDb(db, () async {
        await expectLater(
          const AdminHandler().clearPasswordReset(
            authorization: caller.authorization,
            email: 'a@example.com',
            table: 'users',
          ),
          throwsA(isA<TableAccessDeniedException>()),
        );
        expect(db.acted, isEmpty);
      });
    });

    test('passwordResetRequirement refuses $who', () async {
      // The READ is gated too. Whether a given account is locked out is not a
      // fact an unauthorized caller should be able to probe for.
      final db = _StubZonaiDb(jwt: caller.jwt);

      await withDb(db, () async {
        await expectLater(
          const AdminHandler().passwordResetRequirement(
            authorization: caller.authorization,
            email: 'a@example.com',
            table: 'users',
          ),
          throwsA(isA<TableAccessDeniedException>()),
        );
        expect(db.acted, isEmpty);
      });
    });
  }

  test('an admin acts on the NAMED table, not the resolved admin one', () async {
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    await withDb(db, () async {
      final result = await const AdminHandler().requirePasswordReset(
        authorization: 'Bearer admin-token',
        email: 'a@example.com',
        table: 'users',
      );

      expect(
        db.requiredTable,
        'users',
        reason:
            'the resolved admin table is `admins`; passing that instead would '
            'look this address up in the wrong collection and do nothing',
      );
      expect(result['table'], 'users');
      expect(db.acted, ['requirePasswordReset']);
    });
  });

  test(
    'attributes the requirement to the admin who set it, not to the CLI',
    () async {
      // `created_by` is how an operator later answers "who locked this account
      // out". `'cli'` is what the command line writes; a dashboard action
      // answering the same would be a lie in the one column that exists to say.
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await withDb(db, () async {
        await const AdminHandler().requirePasswordReset(
          authorization: 'Bearer admin-token',
          email: 'a@example.com',
          table: 'users',
        );

        expect(db.requiredBy, 'acting-admin');
      });
    },
  );

  group('reason', () {
    test('defaults to adminForced when omitted', () async {
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await withDb(db, () async {
        await const AdminHandler().requirePasswordReset(
          authorization: 'Bearer admin-token',
          email: 'a@example.com',
          table: 'users',
        );

        expect(db.requiredReason, PasswordResetReason.adminForced);
      });
    });

    test('accepts the kebab-case spelling an operator would send', () async {
      final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

      await withDb(db, () async {
        await const AdminHandler().requirePasswordReset(
          authorization: 'Bearer admin-token',
          email: 'a@example.com',
          table: 'users',
          reason: 'temporary-password',
        );

        expect(db.requiredReason, PasswordResetReason.temporaryPassword);
      });
    });

    test(
      'REFUSES an unknown value rather than defaulting, and writes nothing',
      () async {
        // This value rides to the locked-out client in the 403's
        // `details.reason`. Falling back to `adminForced` would put a claim in a
        // user-facing body that nobody made.
        final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

        await withDb(db, () async {
          await expectLater(
            const AdminHandler().requirePasswordReset(
              authorization: 'Bearer admin-token',
              email: 'a@example.com',
              table: 'users',
              reason: 'because-i-said-so',
            ),
            throwsA(isA<ArgumentError>()),
          );
          expect(db.acted, isEmpty);
        });
      },
    );
  });

  test('clearing reports whether there was anything to clear', () async {
    // Neither answer is an error -- the operator asked for "this account owes
    // nothing" and gets it either way -- but a typo'd address must not read as
    // a success, so the two are distinguishable on the wire.
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true), clearResult: false);

    await withDb(db, () async {
      final result = await const AdminHandler().clearPasswordReset(
        authorization: 'Bearer admin-token',
        email: 'a@example.com',
        table: 'users',
      );

      expect(result['cleared'], false);
    });
  });

  test('the read answers null for an account that owes nothing', () async {
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    await withDb(db, () async {
      final result = await const AdminHandler().passwordResetRequirement(
        authorization: 'Bearer admin-token',
        email: 'a@example.com',
        table: 'users',
      );

      expect(result['requirement'], isNull);
      expect(db.readTable, 'users');
    });
  });
}

/// A [ZonaiDb] that answers a fixed [Jwt] and records what it was asked to do.
///
/// [acted] is the load-bearing field: the gate's job is to keep it empty for an
/// unauthorized caller.
class _StubZonaiDb implements ZonaiDb {
  _StubZonaiDb({required this.jwt, this.clearResult = true});

  final Jwt? jwt;
  final bool clearResult;

  final List<String> acted = [];
  String? requiredTable;
  String? requiredBy;
  PasswordResetReason? requiredReason;
  String? readTable;

  @override
  Future<Jwt?> parseJwt(String? jwt, {bool allowApiToken = false}) async =>
      this.jwt;

  @override
  Future<(String, List<AuthType>)> adminTable() async =>
      ('admins', const [AuthType.password]);

  @override
  Future<void> requirePasswordReset({
    required String table,
    required String email,
    required PasswordResetReason reason,
    String? byUserId,
  }) async {
    acted.add('requirePasswordReset');
    requiredTable = table;
    requiredReason = reason;
    requiredBy = byUserId;
  }

  @override
  Future<bool> clearPasswordResetRequirement({
    required String table,
    required String email,
  }) async {
    acted.add('clearPasswordResetRequirement');
    return clearResult;
  }

  @override
  Future<PasswordResetRequirement?> passwordResetRequirementForEmail({
    required String table,
    required String email,
  }) async {
    acted.add('passwordResetRequirementForEmail');
    readTable = table;
    return null;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_StubZonaiDb does not stub ${invocation.memberName}',
  );
}
