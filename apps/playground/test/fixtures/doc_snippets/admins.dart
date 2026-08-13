// Stand-in for the `admins` table the docs invent when they talk about admin
// claims. See tasks.dart for why these fixtures exist and when to extend them.
//
// It carries `AsAdmin` because that is the whole point of the pages that use
// it: `AsAdmin` is what puts `admin.isAdmin`/`admin.canEdit` on the JWT.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Admin {
  const Admin({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.isVerified,
    required this.createdAt,
  });

  final AdminsId id;
  final String email;
  final String passwordHash;
  final bool isVerified;
  final DateTime createdAt;
}

final class AdminTable extends AuthTable<Admin> with PasswordAuth, AsAdmin {
  AdminTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: AdminsId.new,
        generate: AdminsId.generate,
      ),
      email = $.email('email', (s) => s.email),
      passwordHash = $.password('password', (s) => s.passwordHash),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  @override
  Admin fromRow(RowReader read) => Admin(
    id: read(id),
    email: read(email),
    passwordHash: read(passwordHash),
    isVerified: read(isVerified),
    createdAt: read(createdAt),
  );

  final IdColumn<AdminsId> id;
  final EmailColumn email;
  final PasswordColumn passwordHash;
  final IsVerifiedColumn isVerified;
  final DateTimeColumn createdAt;
}

final admins = authTable('admins', AdminTable.new);
