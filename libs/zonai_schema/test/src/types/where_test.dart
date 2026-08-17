import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/src/types/where.dart';
import 'package:zonai_schema/src/types/where_sql.dart';

void main() {
  void expectRoundTrip(Where where) {
    final json = where.toJson();
    final restored = Where.fromJson(json);
    expect(restored.toJson(), json);
  }

  group(Where, () {
    test('shorthand {column: {eq: value}} parses', () {
      final where = Where.fromJson({
        'id': {'eq': 'tk_abc123'},
      });
      expect(where, isA<Eq>());
      expect((where as Eq).column, 'id');
      expect(where.value, 'tk_abc123');
    });

    test('shorthand {column: {eq: bool}} parses', () {
      final where = Where.fromJson({
        'isComplete': {'eq': false},
      });
      expect(where, isA<Eq>());
      expect((where as Eq).value, isFalse);
    });

    test('shorthand rejects unknown ops', () {
      expect(
        () => Where.fromJson({
          'id': {'nope': 'x'},
        }),
        throwsArgumentError,
      );
    });

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

    test('In and NotIn survive jsonEncode/jsonDecode', () {
      for (final where in <Where>[
        In('id', <Object>[1, 2, 3]),
        NotIn('status', <Object>['open', 'pending']),
      ]) {
        final decoded =
            jsonDecode(jsonEncode(where.toJson())) as Map<String, dynamic>;
        expect(Where.fromJson(decoded).toJson(), where.toJson());
      }
    });

    test('DateTime serializes as epoch ms for JSON and SQL', () {
      final at = DateTime.utc(2024, 6, 1, 12, 30);
      final ms = at.millisecondsSinceEpoch;

      expectRoundTrip(Lt('timestamp', at));
      expect(Lt('timestamp', at).toJson()['value'], ms);

      final restored = Where.fromJson(Lt('timestamp', at).toJson()) as Lt;
      expect(restored.value, ms);
      final (whereSql, whereParams) = restored.sql('_log');
      expect(whereSql, contains('<'));
      expect(whereParams, [ms]);
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

  // `Null` and `NotNull` cannot be exported from `zonai_client`'s barrel: an
  // explicit import outranks the implicit `dart:core` one, so every `Null` a
  // consumer wrote would mean the where clause. These factories are how the two
  // clauses stay constructible while the two names stay unexported, so they are
  // load-bearing for the client barrel rather than sugar.
  group('Where.isNull / Where.isNotNull', () {
    test('isNull builds a Null clause', () {
      const where = Where.isNull('deleted_at');
      expect(where, isA<Null>());
      expect(where.toJson(), {'type': 'is_null', 'column': 'deleted_at'});
    });

    test('isNotNull builds a NotNull clause', () {
      const where = Where.isNotNull('deleted_at');
      expect(where, isA<NotNull>());
      expect(where.toJson(), {'type': 'not_null', 'column': 'deleted_at'});
    });

    test('both round-trip through fromJson', () {
      expectRoundTrip(const Where.isNull('a'));
      expectRoundTrip(const Where.isNotNull('b'));
    });
  });
}
