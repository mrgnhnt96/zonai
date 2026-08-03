import 'dart:convert';

import 'package:revali_router/utils/coerce.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  test('StreamBody round-trips through jsonEncode/jsonDecode', () {
    const original = StreamBody(table: 'contacts', where: Null('deleted_at'));

    final decoded = jsonDecode(jsonEncode(original.toJson())) as Map;
    final parsed = StreamBody.fromJson(Map<String, dynamic>.from(decoded));

    expect(parsed.table, 'contacts');
    expect(parsed.where, isA<Null>());
    expect(parsed.expand, isEmpty);
  });

  test('StreamBody survives Revali-style query coercion', () {
    const original = StreamBody(table: 'contacts', where: Null('deleted_at'));

    final parsed = StreamBody.fromJson(
      Map<String, dynamic>.from(coerce(jsonEncode(original.toJson())) as Map),
    );

    expect(parsed.table, 'contacts');
    expect(parsed.expand, isEmpty);
  });
}
