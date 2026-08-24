import 'package:zonai_forced_password_reset/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Admin {
  Admin({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
    required this.createdAt,
    this.updatedAt,
  });

  final AdminsId id;
  final String email;
  final bool isVerified;
  final String passwordHash;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

/// The `AsAdmin` password collection -- what `zonai db admin
/// require-password-reset` resolves through `adminPasswordTable()`.
final class AdminTable extends AuthTable<Admin> with PasswordAuth, AsAdmin {
  AdminTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: AdminsId.new,
        generate: AdminsId.generate,
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Admin fromRow(RowReader read) {
    return Admin(
      id: read(id),
      email: read(email),
      isVerified: read(isVerified),
      passwordHash: read(passwordHash),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<AdminsId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final admins = authTable('admins', AdminTable.new);
