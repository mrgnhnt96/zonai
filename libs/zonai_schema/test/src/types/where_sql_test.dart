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
            <String, dynamic>{'type': 'is_null', 'column': 'deleted_at'},
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

    test(
      'DateTime values are bound as milliseconds, strings as parameters',
      () {
        final at = DateTime.utc(2024, 6, 1, 12, 30);
        final ms = at.millisecondsSinceEpoch;

        final (ltSql, ltParams) = Lt('timestamp', at).sql('_log');
        expect(ltSql, '"_log"."timestamp" < ?');
        expect(ltParams, [ms]);

        final (eqIntSql, eqIntParams) = const Eq('id', 42).sql('items');
        expect(eqIntSql, '"items"."id" = ?');
        expect(eqIntParams, [42]);

        final (eqStrSql, eqStrParams) = const Eq('title', 't').sql('items');
        expect(eqStrSql, '"items"."title" = ?');
        expect(eqStrParams, ['t']);
      },
    );

    test('JSON round-trip preserves SQL for DateTime columns', () {
      final at = DateTime.utc(2024, 6, 1, 12, 30);
      final (beforeSql, beforeParams) = Lt('timestamp', at).sql('_log');
      final (afterSql, afterParams) = Where.fromJson(
        Lt('timestamp', at).toJson(),
      ).sql('_log');
      expect(afterSql, beforeSql);
      expect(afterParams, beforeParams);
    });

    test('In JSON round-trip produces IN with placeholders and values', () {
      const before = In('level', <Object>['request', 'trace', 'verbose']);
      final after = Where.fromJson(before.toJson()) as In;
      expect(after.values, ['request', 'trace', 'verbose']);

      final (sql, params) = after.sql('_log');
      expect(sql, '"_log"."level" IN (?, ?, ?)');
      expect(params, ['request', 'trace', 'verbose']);
    });
  });
}
