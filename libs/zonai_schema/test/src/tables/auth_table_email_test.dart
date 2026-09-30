import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/introspect.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// An auth table's email is declared lowercase, so `Ann@x.com` and
/// `ann@x.com` are one account -- and, because it is a declaration, `generate`
/// migrates the rows an existing app already has (issue #37).

final class _Row {
  const _Row({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
  });

  final UnknownId id;
  final String email;
  final bool isVerified;
  final String passwordHash;
}

final class _UserTable extends AuthTable<_Row> with PasswordAuth {
  _UserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UnknownId.new,
        generate: () => UnknownId(Id.generate('row')),
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash);

  final IdColumn<UnknownId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;

  @override
  _Row fromRow(RowReader read) => _Row(
    id: read(id),
    email: read(email),
    isVerified: read(isVerified),
    passwordHash: read(passwordHash),
  );
}

final _users = authTable('users', _UserTable.new);

/// Password AND OAuth. OAuth provisions a second row for an address it will
/// not link (`OAuthLinking.never`, or `byVerifiedEmail` with an unverified
/// email), so an email here is deliberately not unique.
final class _MixedUserTable extends _UserTable with OAuth {
  _MixedUserTable(super.$);

  @override
  List<OAuthProvider> get oauthProviders => [
    OAuthProvider.custom(
      id: 'idp',
      displayName: 'idp',
      endpoints: const OAuthEndpoints(
        authorization: 'https://idp.example/authorize',
        token: 'https://idp.example/token',
      ),
      scopes: const ['openid'],
      claims: const OAuthClaimMap(subject: 'sub', email: 'email'),
      clientId: 'cid',
      clientSecret: 'secret',
    ),
  ];
}

final _mixedUsers = authTable('mixed_users', _MixedUserTable.new);

// An `extra` callback replaces the default indexes; it must not also drop the
// email declaration.
final _customUsers = authTable('custom_users', _UserTable.new, (table) {
  uniqueIndex('custom_users.id_unique').on(table.id);
});

Map<String, Object?> _snapshot() => buildSnapshot([
  _users,
  _customUsers,
  _mixedUsers,
], dialect: const SQLiteDialect());

Map<String, Object?> _tableSnapshot(String name) =>
    (_snapshot()['tables']! as Map)[name] as Map<String, Object?>;

Future<PerformOperationResponse> _dispatch(OperationRequest request) async {
  final ops = DbOperations(operations: const [], tables: [_users]);
  return (await ops.dispatch(request))! as PerformOperationResponse;
}

void main() {
  group('auth table email', () {
    for (final table in ['users', 'custom_users']) {
      test('$table: is declared lowercase in the snapshot', () {
        final snapshot = _tableSnapshot(table);
        final email = (snapshot['columns']! as Map)['email']! as Map;

        expect(email['normalize'], 'lowercase');
        expect(
          (snapshot['checks']! as Map)['${table}_email_lowercase'],
          '"email" = LOWER("email")',
        );
      });
    }

    test('sign-in looks the account up by the lowercased address', () async {
      final response = await _dispatch(
        ViewAuthOperationRequest(
          table: 'users',
          payload: const PasswordAuthOperationPayload.get(
            email: 'Ann@Example.COM',
          ),
          jwt: null,
        ),
      );

      expect(response.values, contains('ann@example.com'));
      expect(response.values, isNot(contains('Ann@Example.COM')));
    });

    test('sign-up stores the lowercased address', () async {
      final response = await _dispatch(
        CreateAuthOperationRequest(
          table: 'users',
          payload: const PasswordAuthOperationPayload.save(
            email: 'Ann@Example.COM',
            passwordHash: 'hash',
            object: null,
          ),
          jwt: null,
        ),
      );

      expect(response.values, contains('ann@example.com'));
      expect(response.values, isNot(contains('Ann@Example.COM')));
    });
  });

  // The default indexes used to test `S case PasswordAuth(...)` -- a pattern
  // matched against the table's TYPE, which is a `Type` object and never a
  // `PasswordAuth` -- so the email index was never declared, while the docs
  // promise `TEXT UNIQUE`.
  group('auth table default indexes', () {
    Map<String, Object?> indexOn(String name) {
      final indexes = _snapshot()['indexes']! as Map;
      return indexes[name] as Map<String, Object?>? ?? const {};
    }

    test('declares the unique id index', () {
      // Positive control: the same code path's unconditional half.
      expect(indexOn('users.id_unique'), {
        'name': 'users.id_unique',
        'tableName': 'users',
        'columns': ['id'],
        'isUnique': true,
      });
    });

    test('declares a unique index on email for a PasswordAuth table', () {
      expect(indexOn('users.email_unique'), {
        'name': 'users.email_unique',
        'tableName': 'users',
        'columns': ['email'],
        'isUnique': true,
      });
    });

    test('declares no unique email index when the table also has OAuth', () {
      expect(indexOn('mixed_users.id_unique'), isNotEmpty);
      expect(indexOn('mixed_users.email_unique'), isEmpty);
    });

    test('an `extra` callback replaces the default indexes', () {
      expect(indexOn('custom_users.id_unique'), isNotEmpty);
      expect(indexOn('custom_users.email_unique'), isEmpty);
    });
  });
}
