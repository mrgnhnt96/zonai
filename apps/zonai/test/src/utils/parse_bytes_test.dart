import 'package:test/test.dart';
import 'package:zonai/src/utils/parse_bytes.dart';

void main() {
  group('parseBytes', () {
    test('reads a bare count as bytes', () {
      expect(parseBytes('1024'), 1024);
      expect(parseBytes('1'), 1);
    });

    test('reads powers-of-1024 suffixes, case and space insensitive', () {
      expect(parseBytes('1kb'), 1024);
      expect(parseBytes('512mb'), 512 * 1024 * 1024);
      expect(parseBytes('1GB'), 1024 * 1024 * 1024);
      expect(parseBytes('2 tb'), 2 * 1024 * 1024 * 1024 * 1024);
      expect(parseBytes('  256MB  '), 256 * 1024 * 1024);
      expect(parseBytes('900b'), 900);
    });

    test('1024 rather than 1000, matching what df and page maths mean', () {
      // Getting this wrong understates a ceiling by ~7% at GB scale, which
      // would be invisible until the cap bit earlier than the operator
      // configured it to.
      expect(parseBytes('1gb'), isNot(1000000000));
      expect(parseBytes('1gb'), 1073741824);
    });

    test('rejects zero, which would stop the database accepting a row', () {
      expect(parseBytes('0'), isNull);
      expect(parseBytes('0mb'), isNull);
    });

    test('rejects anything it cannot stand behind', () {
      expect(parseBytes(''), isNull);
      expect(parseBytes('mb'), isNull);
      expect(parseBytes('-5mb'), isNull);
      expect(parseBytes('1.5gb'), isNull, reason: 'no fractional sizes');
      expect(parseBytes('1pb'), isNull, reason: 'unsupported unit');
      expect(parseBytes('512 megabytes'), isNull);
      expect(parseBytes('1gb extra'), isNull);
    });
  });
}
