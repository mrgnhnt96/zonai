/// Source files written when initializing a new Zonai project.
library;

import 'dart:convert';
import 'dart:math';

const initIdsDart = '''
import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);

  factory Id.fromJson(String json) {
    final parts = json.split('_');

    if (parts.length != 2) {
      throw ArgumentError('Invalid ID format: \$json');
    }

    return switch (parts[1]) {
      AdminsId._suffix => AdminsId(json),
      _ => throw ArgumentError('Invalid ID format: \$json'),
    };
  }

  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is Id && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class AdminsId extends Id {
  AdminsId(String value)
      : assert(() {
          final parts = value.split('_');
          return parts.length == 2 && parts[1] == _suffix;
        }(), 'Expected an ID with suffix \$_suffix, got \$value'),
        super(value);

  factory AdminsId.generate() => AdminsId(z.Id.generate(_suffix));

  static const _suffix = 'ad';
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

/// A cryptographically random 48-byte secret, base64url-encoded.
///
/// Scaffolds used to ship `'change-me-jwt-secret'`, and a placeholder that
/// works is a placeholder nobody replaces — a guessable HS256 key lets anyone
/// mint a token for any user. Generating a real one costs nothing and means
/// the default is safe even when it is never touched. `AppConfig.validate()`
/// now refuses the old placeholders outright, so this is also the only
/// scaffold that would still start.
String generateSecret() {
  final random = Random.secure();
  final bytes = List<int>.generate(48, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String initDbConfigDart() =>
    '''
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    // Generated for this project. Rotate by setting PASSWORD_SECRET /
    // JWT_SECRET in the environment — those win over the values here, so a
    // deployed binary need not contain a secret at all.
    passwordSecret: '${generateSecret()}',
    jwtSecret: '${generateSecret()}',
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
