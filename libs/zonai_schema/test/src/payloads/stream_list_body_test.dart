import 'dart:convert';

import 'package:revali_router/utils/coerce.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  test('StreamListBody round-trips through jsonEncode/jsonDecode', () {
    final original = StreamListBody(
      table: 'contacts',
      where: Null('deleted_at'),
    );

    final decoded = jsonDecode(jsonEncode(original.toJson())) as Map;
    final parsed = StreamListBody.fromJson(Map<String, dynamic>.from(decoded));

    expect(parsed.table, 'contacts');
    expect(parsed.where, isA<Null>());
    expect(parsed.expand, isEmpty);
  });

  test('StreamListBody survives Revali-style query coercion', () {
    final original = StreamListBody(
      table: 'contacts',
      where: Null('deleted_at'),
    );

    final parsed = StreamListBody.fromJson(
      Map<String, dynamic>.from(coerce(jsonEncode(original.toJson())) as Map),
    );

    expect(parsed.table, 'contacts');
    expect(parsed.expand, isEmpty);
  });

  test('StreamListBody with a populated expand round-trips', () {
    final original = StreamListBody(table: 'contacts', expand: const ['owner']);

    final decoded = jsonDecode(jsonEncode(original.toJson())) as Map;
    final parsed = StreamListBody.fromJson(Map<String, dynamic>.from(decoded));

    expect(parsed.expand, ['owner']);
  });
}
