import 'package:zonai_forced_password_reset/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

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

/// `PasswordAuth` AND `OtpAuth` on one collection, which is the whole point
/// of this table: a forced reset is a statement about the PASSWORD
/// credential, so the OTP door must stay open while the password door is
/// shut. A password-only table could not tell the two apart.
final class UserTable extends AuthTable<User> with PasswordAuth, OtpAuth {
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
  User fromRow(RowReader read) {
    return User(
      id: read(id),
      email: read(email),
      isVerified: read(isVerified),
      passwordHash: read(passwordHash),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final users = authTable('users', UserTable.new);
