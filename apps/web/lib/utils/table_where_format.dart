import 'dart:convert';

import 'package:zonai_schema/payloads.dart';

/// Pretty-printed JSON for a [ListBody] filter request.
String formatListBodyJson({required String table, required Where where}) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(ListBody(table: table, where: where).toJson());
}

/// Dart source for a [ListBody] filter request (zonai_schema payloads).
String formatListBodyDart({required String table, required Where where}) {
  // indent: 1 aligns nested And/Or items under the `where:` field in ListBody.
  final whereExpr = formatWhereDart(where, indent: 1);
  return '''
// import 'package:zonai_schema/zonai_schema.dart';

ListBody(
  table: '$table',
  where: $whereExpr,
)'''
      .trim();
}

/// Pretty-printed JSON for a [Where] clause only.
String formatWhereJson(Where where) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(where.toJson());
}

/// Dart source for a [Where] clause (zonai_schema payloads).
String formatWhereDart(Where where, {int indent = 0}) {
  return switch (where) {
    Eq(:final column, :final value) => "Eq('$column', ${_dartLiteral(value)})",
    Null(:final column) => "Null('$column')",
    NotNull(:final column) => "NotNull('$column')",
    Gt(:final column, :final value) => "Gt('$column', ${_dartLiteral(value)})",
    Gte(:final column, :final value) => "Gte('$column', ${_dartLiteral(value)})",
    Lt(:final column, :final value) => "Lt('$column', ${_dartLiteral(value)})",
    Lte(:final column, :final value) => "Lte('$column', ${_dartLiteral(value)})",
    In(:final column, :final values) => "In('$column', ${_dartListLiteral(values)})",
    NotIn(:final column, :final values) => "NotIn('$column', ${_dartListLiteral(values)})",
    Contains(:final column, :final value) => "Contains('$column', ${_dartLiteral(value)})",
    NotContains(:final column, :final value) => "NotContains('$column', ${_dartLiteral(value)})",
    StartsWith(:final column, :final value) => "StartsWith('$column', ${_dartLiteral(value)})",
    EndsWith(:final column, :final value) => "EndsWith('$column', ${_dartLiteral(value)})",
    And(:final conditions) ||
    Or(:final conditions) => _formatCompound(where is And ? 'And' : 'Or', conditions, indent: indent),
  };
}

String _formatCompound(String name, List<Where> conditions, {required int indent}) {
  if (conditions.length == 1) {
    return formatWhereDart(conditions.single, indent: indent);
  }

  final pad = '  ' * indent;
  final innerPad = '  ' * (indent + 1);
  final items = [for (final condition in conditions) '$innerPad${formatWhereDart(condition, indent: indent + 1)},'];
  return '$name([\n${items.join('\n')}\n$pad])';
}

String _dartListLiteral(List<Object> values) {
  return '[${values.map(_dartLiteral).join(', ')}]';
}

String _dartLiteral(Object value) {
  return switch (value) {
    String s => "'${_escapeDartString(s)}'",
    num n => n.toString(),
    bool b => b.toString(),
    DateTime d =>
      'DateTime.utc(${d.year}, ${d.month}, ${d.day}, ${d.hour}, ${d.minute}, ${d.second}, ${d.millisecond})',
    _ => "'${_escapeDartString(value.toString())}'",
  };
}

String _escapeDartString(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
