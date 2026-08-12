import 'package:test/test.dart';
import 'package:zonai/src/utils/parse_duration.dart';

void main() {
  group('parseDuration', () {
    test('parses each supported unit', () {
      expect(parseDuration('90s'), const Duration(seconds: 90));
      expect(parseDuration('30m'), const Duration(minutes: 30));
      expect(parseDuration('24h'), const Duration(hours: 24));
      expect(parseDuration('7d'), const Duration(days: 7));
      expect(parseDuration('2w'), const Duration(days: 14));
    });

    test('is case-insensitive and tolerates surrounding space', () {
      expect(parseDuration('7D'), const Duration(days: 7));
      expect(parseDuration('  7d  '), const Duration(days: 7));
      expect(parseDuration('7 d'), const Duration(days: 7));
    });

    test('accepts zero and large values', () {
      expect(parseDuration('0d'), Duration.zero);
      expect(parseDuration('3650d'), const Duration(days: 3650));
    });

    test('rejects a bare number', () {
      // `--older-than 7` is ambiguous -- seven of what? Better to ask than to
      // pick a unit and delete on the user's behalf.
      expect(parseDuration('7'), isNull);
    });

    test('rejects unsupported and ambiguous units', () {
      // Months and years have no fixed length; supporting them would mean
      // silently choosing a definition.
      expect(parseDuration('1mo'), isNull);
      expect(parseDuration('1y'), isNull);
      expect(parseDuration('7ms'), isNull);
    });

    test('rejects malformed input', () {
      expect(parseDuration(''), isNull);
      expect(parseDuration('d'), isNull);
      expect(parseDuration('last tuesday'), isNull);
      expect(parseDuration('-7d'), isNull);
      expect(parseDuration('7.5d'), isNull);
      expect(parseDuration('7d8h'), isNull);
    });
  });
}
