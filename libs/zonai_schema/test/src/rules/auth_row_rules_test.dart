import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _UserId implements Id {
  const _UserId(this.value);

  @override
  final String value;
}

class _User {
  const _User({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
    required this.name,
  });

  final _UserId id;
  final String email;
  final bool isVerified;
  final String passwordHash;
  final String name;
}

final class _UserTable extends AuthTable<_User> with PasswordAuth {
  _UserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _UserId.new,
        generate: () => const _UserId('generated'),
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      name = $.text('name', (s) => s.name);

  @override
  _User fromRow(RowReader read) => _User(
    id: read(id),
    email: read(email),
    isVerified: read(isVerified),
    passwordHash: read(passwordHash),
    name: read(name)!,
  );

  @override
  final IdColumn<_UserId> id;

  @override
  final EmailColumn email;

  @override
  final IsVerifiedColumn isVerified;

  @override
  final PasswordColumn passwordHash;

  final TextColumn name;
}

class _UserRowRules extends AuthRowRules<_UserTable, _User> {
  const _UserRowRules(super.schema);
}

/// Identical to [_UserTable] but for `AsAdmin` — which is the whole point.
/// `AsAdmin` is not a per-row property: `DbOperations._getJwtConfig` sets
/// `isAdmin: admin != null` from the SCHEMA, so every row this table
/// authenticates gets an admin JWT.
final class _AdminTable extends AuthTable<_User> with PasswordAuth, AsAdmin {
  _AdminTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _UserId.new,
        generate: () => const _UserId('generated'),
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      name = $.text('name', (s) => s.name);

  @override
  _User fromRow(RowReader read) => _User(
    id: read(id),
    email: read(email),
    isVerified: read(isVerified),
    passwordHash: read(passwordHash),
    name: read(name)!,
  );

  @override
  final IdColumn<_UserId> id;

  @override
  final EmailColumn email;

  @override
  final IsVerifiedColumn isVerified;

  @override
  final PasswordColumn passwordHash;

  final TextColumn name;
}

class _AdminRowRules extends AuthRowRules<_AdminTable, _User> {
  const _AdminRowRules(super.schema);
}

/// An app that deliberately wants open registration on an admin table. The
/// override is the opt-in the default exists to force.
class _OpenAdminRowRules extends AuthRowRules<_AdminTable, _User> {
  const _OpenAdminRowRules(super.schema);

  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
}

void main() {
  late _UserTable users;
  late _UserRowRules rules;
  late _AdminTable admins;
  late _AdminRowRules adminRules;

  setUp(() {
    users = authTable('_test_users', _UserTable.new);
    rules = _UserRowRules(users);
    admins = authTable('_test_admins', _AdminTable.new);
    adminRules = _AdminRowRules(admins);
  });

  Jwt _jwtFor(String userId) => Jwt.create(
    userId: userId,
    table: '_test_users',
    user: const {},
    jwtId: JwtId('jwt-1'),
    expiresIn: const Duration(hours: 1),
    claims: const {},
  );

  // `Jwt.create` hard-codes `admin: (isAdmin: false, canEdit: null)` — an
  // admin JWT only comes out of the token pipeline, so the test builds one
  // through the primary constructor.
  Jwt _adminJwt() => Jwt(
    userId: const UnknownId('admin-1'),
    table: '_test_admins',
    user: const {},
    jwtId: JwtId('jwt-admin'),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    claims: const {},
    admin: (isAdmin: true, canEdit: true),
  );

  test('canView allows the signed-in user to read their own row', () async {
    const row = _User(
      id: _UserId('user-1'),
      email: 'a@b.com',
      isVerified: true,
      passwordHash: 'hash',
      name: 'Ada',
    );

    expect(await rules.canView(_jwtFor('user-1'), row), isTrue);
  });

  test(
    'canView denies access when jwt user id does not match row id',
    () async {
      const row = _User(
        id: _UserId('user-1'),
        email: 'a@b.com',
        isVerified: true,
        passwordHash: 'hash',
        name: 'Ada',
      );

      expect(await rules.canView(_jwtFor('user-2'), row), isFalse);
    },
  );

  test('canUpdate matches the signed-in user against before, not after — the '
      "id doesn't change across an update, but before is the row that's "
      'actually persisted right now', () async {
    const before = _User(
      id: _UserId('user-1'),
      email: 'a@b.com',
      isVerified: true,
      passwordHash: 'hash',
      name: 'Ada',
    );
    const after = _User(
      id: _UserId('user-1'),
      email: 'a@b.com',
      isVerified: true,
      passwordHash: 'hash',
      name: 'Ada Lovelace',
    );

    expect(await rules.canUpdate(_jwtFor('user-1'), before, after), isTrue);
    expect(await rules.canUpdate(_jwtFor('user-2'), before, after), isFalse);
  });

  // ---------------------------------------------------------------------
  // AsAdmin + open sign-up.
  //
  // The two halves are each defensible alone, which is why nothing caught
  // the pair. `AsAdmin` grants `isAdmin` per SCHEMA, not per row, and
  // `/auth/sign-up` is anonymous — so before this default, putting `AsAdmin`
  // on a public sign-up table handed admin to every registrant, silently and
  // without a single line of app code saying so.
  //
  // The non-admin cases below are the control: they assert the default did
  // not simply get tightened for everyone, which would "fix" this by
  // breaking ordinary sign-up.
  // ---------------------------------------------------------------------

  group('canSignUp on an AsAdmin table', () {
    test('denies an anonymous sign-up by default', () async {
      expect(await adminRules.canSignUp(null, AuthType.password), isFalse);
    });

    test('denies a caller holding a plain, non-admin JWT', () async {
      expect(
        await adminRules.canSignUp(_jwtFor('user-1'), AuthType.password),
        isFalse,
      );
    });

    test('still allows an existing admin to create another admin', () async {
      expect(
        await adminRules.canSignUp(_adminJwt(), AuthType.password),
        isTrue,
      );
    });

    test('is denied for every auth type, not just password', () async {
      for (final type in AuthType.values) {
        expect(
          await adminRules.canSignUp(null, type),
          isFalse,
          reason: 'AuthType.${type.name} should be denied on an AsAdmin table',
        );
      }
    });

    test('an app can opt back in by overriding canSignUp', () async {
      final open = _OpenAdminRowRules(admins);

      expect(await open.canSignUp(null, AuthType.password), isTrue);
    });
  });

  group('canSignUp on a table WITHOUT AsAdmin', () {
    test('still allows anonymous sign-up for a supported auth type', () async {
      expect(await rules.canSignUp(null, AuthType.password), isTrue);
    });

    test('still refuses an auth type the table does not support', () async {
      // `_UserTable` mixes in `PasswordAuth` only.
      expect(await rules.canSignUp(null, AuthType.otp), isFalse);
      expect(await rules.canSignUp(null, AuthType.magicLink), isFalse);
    });
  });

  test('canSignIn is unchanged on an AsAdmin table — closing sign-up must not '
      'lock out the admins the table already has', () async {
    expect(await adminRules.canSignIn(null, AuthType.password), isTrue);
  });
}
