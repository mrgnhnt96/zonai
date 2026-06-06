import 'dart:convert';

import 'package:revali_router/utils/coerce.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  test('ListBody survives Revali-style query coercion when where is present', () {
    final original = ListBody(
      table: 'tasks',
      where: Contains('name', 'foo'),
      limit: 50,
      offset: 0,
    );

    final wire = original.toJson();
    expect(wire['where'], isA<Map>());

    // Client sends `body` as one JSON-encoded query value; server runs [coerce] on it.
    final bodyParam = jsonEncode(wire);
    final parsed = ListBody.fromJson(coerce(bodyParam) as Map);
    expect(parsed.table, 'tasks');
    expect(parsed.where, isA<Contains>());
    expect((parsed.where as Contains).column, 'name');
    expect((parsed.where as Contains).value, 'foo');
    expect(parsed.limit, 50);
    expect(parsed.offset, 0);
  });

  test('ListBody is-null where survives Revali-style query coercion', () {
    final original = ListBody(table: 'tasks', where: Null('deleted_at'));

    final parsed = ListBody.fromJson(
      coerce(jsonEncode(original.toJson())) as Map,
    );
    expect(parsed.where, isA<Null>());
    expect((parsed.where as Null).column, 'deleted_at');
  });
}
