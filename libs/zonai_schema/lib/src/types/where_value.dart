import 'dart:convert';

/// Normalizes [value] for JSON so wire format matches DB encodings (e.g. DateTime → ms).
Object? whereValueToJsonEncodable(Object? value) {
  return switch (value) {
    DateTime d => d.millisecondsSinceEpoch,
    final Map m => {
      for (final entry in m.entries)
        entry.key.toString(): whereValueToJsonEncodable(entry.value),
    },
    final List l => [for (final e in l) whereValueToJsonEncodable(e)],
    _ => value,
  };
}

Object serializeWhereValue(Object value) {
  return jsonDecode(jsonEncode(whereValueToJsonEncodable(value))) as Object;
}

List<Object> serializeWhereValues(List<Object> values) {
  return (jsonDecode(jsonEncode(whereValueToJsonEncodable(values))) as List)
      .cast<Object>();
}

/// SQL literal for a [Where] comparison value (matches [whereValueToJsonEncodable]).
String whereValueSqlLiteral(Object value) {
  return switch (value) {
    DateTime d => '${d.millisecondsSinceEpoch}',
    num n => n.toString(),
    bool b => b ? '1' : '0',
    String s => "'${escapeSqlString(s)}'",
    _ => "'${escapeSqlString(value.toString())}'",
  };
}

String escapeSqlString(Object s) => switch (s) {
  final String s => s,
  _ => s.toString(),
}.replaceAll("'", "''");
