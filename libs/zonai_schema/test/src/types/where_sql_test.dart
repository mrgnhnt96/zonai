import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_schema/src/types/where_sql.dart';

void main() {
  group(WhereSql, () {
    test('fromJson parses collection and Where data', () {
      final sql = WhereSql.fromJson(<String, dynamic>{
        'collection': 'items',
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
  });
}
