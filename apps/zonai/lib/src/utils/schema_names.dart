import 'dart_name_format.dart';

/// Naming helpers for generated schema and ID types.
String pluralizePascal(String singular) {
  if (singular.isEmpty) return singular;

  if (singular.endsWith('y') && singular.length > 1) {
    final before = singular[singular.length - 2];
    if (!'aeiou'.contains(before.toLowerCase())) {
      return '${singular.substring(0, singular.length - 1)}ies';
    }
  }

  if (singular.endsWith('s') ||
      singular.endsWith('x') ||
      singular.endsWith('z') ||
      singular.endsWith('ch') ||
      singular.endsWith('sh')) {
    return '${singular}es';
  }

  return '${singular}s';
}

/// Derives a two-character ID suffix from [tableName], avoiding [used].
String uniqueIdSuffix(String tableName, Set<String> used) {
  final normalized = tableName.replaceAll('_', '');
  if (normalized.isEmpty) {
    return _unusedSuffix('id', used);
  }

  final candidates = <String>[
    if (normalized.length >= 2) normalized.substring(0, 2),
    if (normalized.length >= 2)
      '${normalized[0]}${normalized[normalized.length - 1]}',
    for (var i = 1; i < normalized.length; i++)
      '${normalized[0]}${normalized[i]}',
  ];

  for (final candidate in candidates) {
    if (!used.contains(candidate)) return candidate;
  }

  return _unusedSuffix(normalized.substring(0, 1), used);
}

String _unusedSuffix(String prefix, Set<String> used) {
  for (var i = 0; i < 26; i++) {
    final candidate = '$prefix${String.fromCharCode(97 + i)}';
    if (!used.contains(candidate)) return candidate;
  }

  throw StateError('Unable to derive a unique ID suffix');
}

final _suffixPattern = RegExp(r"static const _suffix = '([^']+)'");

Set<String> parseIdSuffixes(String idsFileContent) {
  return _suffixPattern
      .allMatches(idsFileContent)
      .map((match) => match.group(1)!)
      .toSet();
}

class SchemaNames {
  const SchemaNames({
    required this.entityClass,
    required this.pluralClass,
    required this.idClass,
    required this.tableClass,
    required this.tableName,
    required this.getter,
    required this.fileName,
    required this.idSuffix,
  });

  factory SchemaNames.fromEntityClass(
    String entityClass, {
    required Set<String> usedIdSuffixes,
  }) {
    final pluralClass = pluralizePascal(entityClass);
    final tableName = pascalToSnake(pluralClass);

    return SchemaNames(
      entityClass: entityClass,
      pluralClass: pluralClass,
      idClass: '${pluralClass}Id',
      tableClass: '${entityClass}Table',
      tableName: tableName,
      getter: tableName,
      fileName: '$tableName.dart',
      idSuffix: uniqueIdSuffix(tableName, usedIdSuffixes),
    );
  }

  final String entityClass;
  final String pluralClass;
  final String idClass;
  final String tableClass;
  final String tableName;
  final String getter;
  final String fileName;
  final String idSuffix;
}
