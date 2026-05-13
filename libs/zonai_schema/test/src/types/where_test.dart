import 'package:test/test.dart';
import 'package:zonai_schema/src/types/where.dart';

void main() {
  void expectRoundTrip(Where where) {
    final json = where.toJson();
    final restored = Where.fromJson(json);
    expect(restored.toJson(), json);
  }

  group(Where, () {
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
}
