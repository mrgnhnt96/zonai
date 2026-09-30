import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  group('parseBody', () {
    test('passes a good body through', () {
      final body = CountBody.fromJson({'table': 'notes'});

      expect(body.table, 'notes');
    });

    // Each of these failed differently before: an ArgumentError, a TypeError
    // from a cast, a FormatException. The server can only answer 400 for a
    // type it can recognise, so they all become one.
    final malformed = <String, Object? Function()>{
      'a where that is not a where': () =>
          CountBody.fromJson({'table': 'notes', 'where': <String, Object?>{}}),
      'a field of the wrong type (a cast)': () =>
          CountBody.fromJson({'table': 42}),
      'a missing required field': () => CreateBody.fromJson({'table': 'x'}),
      'a nested value of the wrong type': () =>
          CountBody.fromJson({'table': 'notes', 'where': 'x'}),
    };
    for (final MapEntry(key: label, value: parse) in malformed.entries) {
      test('turns $label into an InvalidBodyException', () {
        expect(parse, throwsA(isA<InvalidBodyException>()));
      });
    }

    test('names the body in the message', () {
      expect(
        () => CountBody.fromJson({'table': 42}),
        throwsA(
          isA<InvalidBodyException>().having(
            (e) => '${e.message}',
            'message',
            startsWith('CountBody:'),
          ),
        ),
      );
    });

    test('is an ArgumentError, for callers that already catch one', () {
      expect(
        () => CountBody.fromJson({'table': 42}),
        throwsA(isA<ArgumentError>()),
      );
    });

    // revali hands only Exceptions to the server's catchers; anything else
    // is a bare 500 before a catcher is asked.
    test('is an Exception, so the server can catch it', () {
      expect(
        () => CountBody.fromJson({'table': 42}),
        throwsA(isA<Exception>()),
      );
    });

    test('rethrows one it is handed unchanged', () {
      final original = InvalidBodyException('already described');

      expect(
        () => parseBody<void>('X', () => throw original),
        throwsA(same(original)),
      );
    });
  });
}
