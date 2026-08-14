import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signin_enumeration_repro/src/ids.dart';

/// A `users` table shaped like the one in the Picto report: alongside the
/// auth columns it carries a **required, non-nullable** `name` that only a
/// sign-up body can supply (`{"object": {"name": ...}}`).
///
/// That required column is what turned the sign-in-falls-through-to-sign-up
/// bug into an HTTP 500 rather than a silently created account.
final class User {
  User({
    required this.id,
    required this.email,
    required this.name,
    required this.isVerified,
    required this.passwordHash,
    required this.createdAt,
    this.updatedAt,
  });

  final UsersId id;
  final String email;
  final String name;
  final bool isVerified;
  final String passwordHash;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class UserTable extends AuthTable<User> with PasswordAuth {
  UserTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UsersId.new,
        generate: UsersId.generate,
      ),
      email = $.email('email', (s) => s.email),
      name = $.text('name', (s) => s.name),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) {
    return User(
      id: read(id),
      email: read(email),
      name: read(name),
      isVerified: read(isVerified),
      passwordHash: read(passwordHash),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final TextColumn name;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final users = authTable('users', UserTable.new);
