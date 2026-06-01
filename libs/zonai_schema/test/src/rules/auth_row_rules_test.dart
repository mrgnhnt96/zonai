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

void main() {
  late _UserTable users;
  late _UserRowRules rules;

  setUp(() {
    users = authTable('_test_users', _UserTable.new);
    rules = _UserRowRules(users);
  });

  Jwt _jwtFor(String userId) => Jwt.create(
    userId: userId,
    table: '_test_users',
    user: const {},
    jwtId: JwtId('jwt-1'),
    expiresIn: const Duration(hours: 1),
    claims: const {},
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
}
