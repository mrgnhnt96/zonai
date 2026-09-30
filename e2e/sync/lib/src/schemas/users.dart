import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_sync_e2e/src/ids.dart';

final class User {
  User({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
    required this.createdAt,
    this.updatedAt,
  });

  final UsersId id;
  final String email;
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
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) => User(
    id: read(id),
    email: read(email),
    isVerified: read(isVerified),
    passwordHash: read(passwordHash),
    createdAt: read(createdAt),
    updatedAt: read(updatedAt),
  );

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final users = authTable('users', UserTable.new);
