import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_schema/src/types/where_sql.dart';

void main() {
  group(WhereSql, () {
    test('fromJson parses collection and Where data', () {
      final sql = WhereSql.fromJson(<String, dynamic>{
        'table': 'items',
        'data': <String, dynamic>{
          'type': 'and',
          'conditions': <dynamic>[
            <String, dynamic>{'type': 'eq', 'column': 'kind', 'value': 'book'},
            <String, dynamic>{'type': 'null', 'column': 'deleted_at'},
          ],
        },
      });

      expect(sql.table, 'items');
      expect(
        sql.data,
        isA<And>().having((a) => a.conditions.length, 'conditions.length', 2),
      );
      final and = sql.data as And;
      expect(and.conditions[0], isA<Eq>());
      expect((and.conditions[0] as Eq).column, 'kind');
      expect((and.conditions[0] as Eq).value, 'book');
      expect(and.conditions[1], isA<Null>());
      expect((and.conditions[1] as Null).column, 'deleted_at');
    });

    test('DateTime and numeric values use unquoted SQL literals', () {
      final at = DateTime.utc(2024, 6, 1, 12, 30);
      final ms = at.millisecondsSinceEpoch;

      expect(
        Lt('timestamp', at).sql('_log'),
        '"_log"."timestamp" < $ms',
      );
      expect(const Eq('id', 42).sql('items'), '"items"."id" = 42');
      expect(const Eq('title', 't').sql('items'), '"items"."title" = \'t\'');
    });

    test('JSON round-trip preserves SQL for DateTime columns', () {
      final at = DateTime.utc(2024, 6, 1, 12, 30);
      final before = Lt('timestamp', at).sql('_log');
      final after = Where.fromJson(Lt('timestamp', at).toJson()).sql('_log');
      expect(after, before);
    });
  });
}
