import 'package:zonai_signup_gate_repro/src/ids.dart';
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

/// All three insert-a-row flows, on one table.
///
/// `OtpAuth` and `MagicLinkAuth` are capability flags -- neither adds a
/// column -- so carrying all three costs nothing here and lets one compiled
/// worker answer for every flow `beforeSignUp` is supposed to gate. The two
/// code flows create the account at VERIFY time, which is exactly why they
/// need their own coverage: the gate has to run at REQUEST time or the code
/// email is already gone.
final class UserTable extends AuthTable<User>
    with PasswordAuth, OtpAuth, MagicLinkAuth {
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
