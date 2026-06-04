import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/table_where_format.dart';

void main() {
  group('formatWhereDart', () {
    test('Eq with string', () {
      expect(formatWhereDart(const Eq('name', 'foo')), "Eq('name', 'foo')");
    });

    test('Null', () {
      expect(formatWhereDart(const Null('email')), "Null('email')");
    });

    test('And with multiple conditions', () {
      final dart = formatWhereDart(
        And([
          const Eq('a', 1),
          const Null('b'),
        ]),
      );
      expect(dart, contains('And(['));
      expect(dart, contains("Eq('a', 1)"));
      expect(dart, contains("Null('b')"));
    });

    test('In list values', () {
      expect(
        formatWhereDart(In('status', <Object>['open', 'pending'])),
        "In('status', ['open', 'pending'])",
      );
    });
  });

  group('formatListBodyDart', () {
    test('includes table and where', () {
      final dart = formatListBodyDart(
        table: 'users',
        where: const Eq('id', 1),
      );
      expect(dart, contains("table: 'users'"));
      expect(dart, contains("Eq('id', 1)"));
      expect(dart, contains('ListBody('));
    });
  });

  group('formatListBodyJson', () {
    test('round-trips through ListBody.fromJson', () {
      final where = And([const Eq('a', 1), const Null('b')]);
      final json = formatListBodyJson(table: 'items', where: where);
      final decoded = ListBody.fromJson(
        (jsonDecode(json) as Map).cast<String, dynamic>(),
      );
      expect(decoded.table, 'items');
      expect(decoded.where?.toJson(), where.toJson());
    });
  });
}
