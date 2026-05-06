import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/utils/where_sql.dart';

void main() {
  void expectRoundTrip(Where where) {
    final json = where.toJson();
    final restored = Where.fromJson(json);
    expect(restored.toJson(), json);
  }

  group('Where', () {
    test('Eq round-trips', () {
      expectRoundTrip(const Eq('col', 'x'));
      expectRoundTrip(const Eq('n', 42));
      expectRoundTrip(const Eq('flag', true));
    });

    test('Null round-trips', () {
      expectRoundTrip(const Null('col'));
    });

    test('NotNull round-trips', () {
      expectRoundTrip(const NotNull('col'));
    });

    test('Gt, Gte, Lt, Lte round-trip', () {
      expectRoundTrip(const Gt('a', 1));
      expectRoundTrip(const Gte('b', 2));
      expectRoundTrip(const Lt('c', 3));
      expectRoundTrip(const Lte('d', 4.5));
    });

    test('In and NotIn round-trip', () {
      expectRoundTrip(In('status', <Object>['open', 'pending']));
      expectRoundTrip(NotIn('id', <Object>[1, 2, 3]));
    });

    test('And round-trips nested conditions', () {
      expectRoundTrip(
        And(<Where>[
          const Eq('a', 1),
          const Null('b'),
          Or(<Where>[const Gt('c', 0), const NotNull('d')]),
        ]),
      );
    });

    test('Or round-trips nested conditions', () {
      expectRoundTrip(
        Or(<Where>[
          In('x', <Object>['a', 'b']),
          And(<Where>[const Lte('y', 9)]),
        ]),
      );
    });

    test('fromJson rejects unknown type', () {
      expect(
        () => Where.fromJson(<String, dynamic>{'type': 'nosuch'}),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'type')),
      );
    });
  });

  group('WhereSql', () {
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

      expect(sql.collection, 'items');
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
