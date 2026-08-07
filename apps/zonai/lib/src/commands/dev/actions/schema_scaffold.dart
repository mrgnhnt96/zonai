import '../../../utils/schema_names.dart';

enum SchemaTableKind { regular, auth }

class SchemaAuthConfig {
  const SchemaAuthConfig({
    this.password = true,
    this.otp = false,
    this.magicLink = false,
    this.isAdmin = false,
    this.canEdit = true,
  });

  final bool password;
  final bool otp;
  final bool magicLink;
  final bool isAdmin;
  final bool canEdit;

  bool get hasAnyAuth => password || otp || magicLink;
}

String scaffoldSchemaSource({
  required SchemaNames names,
  required SchemaTableKind kind,
  SchemaAuthConfig authConfig = const SchemaAuthConfig(),
}) {
  return switch (kind) {
    SchemaTableKind.regular => _scaffoldRegularTable(names),
    SchemaTableKind.auth => _scaffoldAuthTable(names, authConfig),
  };
}

String scaffoldStandaloneIdClass(SchemaNames names) {
  return '''
sealed class ${names.idClass} implements z.Id {
  const ${names.idClass}(this.value);

  factory ${names.idClass}.generate() => ${names.idClass}(z.Id.generate(_suffix));

  static const _suffix = '${names.idSuffix}';

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is z.Id && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
''';
}

String scaffoldUnionIdClass(SchemaNames names) {
  return '''

class ${names.idClass} extends Id {
  const ${names.idClass}(super.value);

  factory ${names.idClass}.generate() => ${names.idClass}(z.Id.generate(_suffix));

  static const _suffix = '${names.idSuffix}';
}
''';
}

String scaffoldInitialIdsFile(SchemaNames names) {
  return '''
import 'package:zonai_schema/zonai_schema.dart' as z;

${scaffoldStandaloneIdClass(names).trim()}
''';
}

String appendUnionIdCase(String content, SchemaNames names) {
  const fallbackCase = "_ => throw ArgumentError('Invalid ID format: \$json'),";
  const indentedFallback = '      $fallbackCase';
  if (!content.contains(indentedFallback)) {
    throw StateError('ids.dart is missing the union ID fallback case');
  }

  final caseLine = '      ${names.idClass}._suffix => ${names.idClass}(json),';
  if (content.contains(caseLine)) return content;

  return content.replaceFirst(
    indentedFallback,
    '$caseLine\n$indentedFallback',
  );
}

String _scaffoldRegularTable(SchemaNames names) {
  return '''
import '../ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ${names.entityClass} {
  ${names.entityClass}({
    required this.id,
    required this.name,
    required this.createdAt,
    this.updatedAt,
  });

  final ${names.idClass} id;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class ${names.tableClass} extends Table<${names.entityClass}> {
  ${names.tableClass}(super.\$)
    : id = \$.id(
        'id',
        (s) => s.id,
        fromString: ${names.idClass}.new,
        generate: ${names.idClass}.generate,
      ),
      name = \$.text('name', (s) => s.name),
      createdAt = \$.createdAt('created_at', (s) => s.createdAt),
      updatedAt = \$.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  ${names.entityClass} fromRow(RowReader read) {
    return ${names.entityClass}(
      id: read(id),
      name: read(name),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<${names.idClass}> id;
  final TextColumn name;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final ${names.getter} = table('${names.tableName}', ${names.tableClass}.new);
''';
}

String _scaffoldAuthTable(SchemaNames names, SchemaAuthConfig authConfig) {
  final mixins = _authMixins(authConfig);
  final passwordEntityField = authConfig.password
      ? '''
    required this.passwordHash,'''
      : '';
  final passwordEntityMember = authConfig.password
      ? '''
  final String passwordHash;'''
      : '';
  final passwordTableColumn = authConfig.password
      ? '''
      passwordHash = \$.password('password', (s) => s.passwordHash),'''
      : '';
  final passwordFromRow = authConfig.password
      ? '''
      passwordHash: read(passwordHash),'''
      : '';
  final passwordTableMember = authConfig.password
      ? '''
  final PasswordColumn passwordHash;'''
      : '';
  final canEditOverride = authConfig.isAdmin && !authConfig.canEdit
      ? '''

  @override
  bool get canEdit => false;'''
      : '';

  return '''
import '../ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ${names.entityClass} {
  ${names.entityClass}({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.isVerified,$passwordEntityField
    this.updatedAt,
  });

  final ${names.idClass} id;
  final String email;
  final DateTime createdAt;
  final bool isVerified;$passwordEntityMember
  final DateTime? updatedAt;
}

final class ${names.tableClass} extends AuthTable<${names.entityClass}>$mixins {
  ${names.tableClass}(super.\$)
    : id = \$.id(
        'id',
        (s) => s.id,
        fromString: ${names.idClass}.new,
        generate: ${names.idClass}.generate,
      ),
      email = \$.email('email', (s) => s.email),
      isVerified = \$.isVerified('is_verified', (s) => s.isVerified),$passwordTableColumn
      createdAt = \$.createdAt('created_at', (s) => s.createdAt),
      updatedAt = \$.updatedAt('updated_at', (s) => s.updatedAt);$canEditOverride

  @override
  ${names.entityClass} fromRow(RowReader read) {
    return ${names.entityClass}(
      id: read(id),
      email: read(email),
      isVerified: read(isVerified),$passwordFromRow
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<${names.idClass}> id;
  final DateTimeColumn createdAt;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;$passwordTableMember
  final ColumnType<DateTime?> updatedAt;
}

final ${names.getter} = authTable('${names.tableName}', ${names.tableClass}.new);
''';
}

String _authMixins(SchemaAuthConfig authConfig) {
  final mixins = <String>[
    if (authConfig.password) 'PasswordAuth',
    if (authConfig.otp) 'OtpAuth',
    if (authConfig.magicLink) 'MagicLinkAuth',
    if (authConfig.isAdmin) 'AsAdmin',
  ];

  if (mixins.isEmpty) return '';
  return ' with ${mixins.join(', ')}';
}
