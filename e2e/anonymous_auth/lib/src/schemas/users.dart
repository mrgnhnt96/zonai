import 'package:zonai_anonymous_auth_fixture/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class User {
  User({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
    required this.createdAt,
    this.displayName,
  });

  final UsersId id;

  /// NULL while the account is anonymous.
  final String? email;
  final bool isVerified;
  final String passwordHash;
  final String? displayName;
  final DateTime createdAt;
}

final class UserTable extends AuthTable<User>
    with OtpAuth, PasswordAuth, AnonymousAuth {
  UserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UsersId.new,
        generate: UsersId.generate,
      ),
      email = $.email<String?>('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      displayName = $.text('display_name', (s) => s.displayName),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  @override
  User fromRow(RowReader read) {
    return User(
      id: read(id),
      email: read(email),
      isVerified: read(isVerified),
      passwordHash: read(passwordHash),
      displayName: read(displayName),
      createdAt: read(createdAt),
    );
  }

  @override
  final IdColumn<UsersId> id;
  @override
  final NullableEmailColumn email;
  @override
  final IsVerifiedColumn isVerified;
  @override
  final PasswordColumn passwordHash;
  final ColumnType<String?> displayName;
  final DateTimeColumn createdAt;

  @override
  Set<String> get anonymousSignUpColumns => const {'display_name'};
}

// A password table without OAuth, so `authTable` declares the unique email
// index itself. The upgrade race test relies on it; NULLs (anonymous
// accounts) never collide under it.
final users = authTable('users', UserTable.new);
