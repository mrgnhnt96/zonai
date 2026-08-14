import 'package:test/test.dart';
import 'package:zonai_logger/zonai_logger.dart';

void main() {
  group('Level.fromString', () {
    const cases = {
      'verbose': Level.verbose,
      'v': Level.verbose,
      'trace': Level.trace,
      't': Level.trace,
      'request': Level.request,
      'r': Level.request,
      'debug': Level.debug,
      'd': Level.debug,
      'info': Level.info,
      'i': Level.info,
      'warning': Level.warning,
      'w': Level.warning,
      'error': Level.error,
      'e': Level.error,
    };

    cases.forEach((input, expected) {
      test('"$input" maps to $expected', () {
        expect(Level.fromString(input), expected);
      });
    });

    test('an unrecognized string maps to null', () {
      expect(Level.fromString('nonsense'), isNull);
    });

    test('null maps to null', () {
      expect(Level.fromString(null), isNull);
    });
  });

  group('Level comparisons', () {
    test('<= is true for the same level and lower levels', () {
      expect(Level.debug <= Level.debug, isTrue);
      expect(Level.debug <= Level.info, isTrue);
      expect(Level.info <= Level.debug, isFalse);
    });

    test('< is strict', () {
      expect(Level.debug < Level.info, isTrue);
      expect(Level.debug < Level.debug, isFalse);
    });

    test('>= is true for the same level and higher levels', () {
      expect(Level.error >= Level.error, isTrue);
      expect(Level.error >= Level.warning, isTrue);
      expect(Level.warning >= Level.error, isFalse);
    });

    test('> is strict', () {
      expect(Level.error > Level.warning, isTrue);
      expect(Level.error > Level.error, isFalse);
    });

    test('severity ordering runs verbose..error, low to high', () {
      const ordered = [
        Level.verbose,
        Level.trace,
        Level.request,
        Level.debug,
        Level.info,
        Level.warning,
        Level.error,
      ];

      for (var i = 0; i < ordered.length - 1; i++) {
        expect(ordered[i] < ordered[i + 1], isTrue, reason: '${ordered[i]} should be < ${ordered[i + 1]}');
      }
    });
  });
}
