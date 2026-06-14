/// Source files written when initializing a new Zonai project.
library;

const initIdsDart = '''
import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class AdminsId implements z.Id {
  const AdminsId(this.value);

  factory AdminsId.generate() => AdminsId(z.Id.generate(_suffix));

  static const _suffix = 'ad';

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is AdminsId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
''';

const initAdminsSchemaDart = '''
import '../ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Admin {
  Admin({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.createdAt,
    required this.isVerified,
    this.updatedAt,
  });

  final AdminsId id;
  final String email;
  final String passwordHash;
  final DateTime createdAt;
  final bool isVerified;
  final DateTime? updatedAt;
}

final class AdminTable extends AuthTable<Admin> with PasswordAuth, AsAdmin {
  AdminTable(super.\$)
    : id = \$.id(
        'id',
        (s) => s.id,
        fromString: AdminsId.new,
        generate: AdminsId.generate,
      ),
      email = \$.email('email', (s) => s.email),
      isVerified = \$.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = \$.password('password', (s) => s.passwordHash),
      createdAt = \$.createdAt('created_at', (s) => s.createdAt),
      updatedAt = \$.updatedAt('updated_at', (s) => s.updatedAt);

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
  final DateTimeColumn createdAt;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;
  final ColumnType<DateTime?> updatedAt;
}

final admins = authTable('admins', AdminTable.new);
''';

const initDbConfigDart = '''
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: 'change-me-password-secret',
    jwtSecret: 'change-me-jwt-secret',
    baseUrl: 'http://localhost:8080',
    email: EmailConfig(
      host: 'smtp.example.com',
      port: 587,
      username: 'user@example.com',
      password: 'change-me',
      from: EmailAddress(address: 'noreply@example.com', name: 'My App'),
    ),
  );
}
''';

const initAdminOperationsDart = '''
import '../schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class AdminOperations extends TableOperations<AdminTable, Admin> {
  AdminOperations() : super(admins);
}

AdminOperations main() => AdminOperations();
''';

const initAdminRulesDart = '''
import '../schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminTableRules main() => AdminTableRules();

final class AdminTableRules extends AuthTableRules<AdminTable, Admin> {
  AdminTableRules() : super(admins);
}
''';
