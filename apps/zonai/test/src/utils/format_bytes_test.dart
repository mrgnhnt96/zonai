import 'package:test/test.dart';
import 'package:zonai/src/utils/format_bytes.dart';

void main() {
  group('formatBytes', () {
    test('leaves small values in bytes, unrounded', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1), '1 B');
      expect(formatBytes(999), '999 B');
    });

    test('steps up a unit at each factor of 1000', () {
      expect(formatBytes(1000), '1.0 KB');
      expect(formatBytes(1000000), '1.0 MB');
      expect(formatBytes(1000000000), '1.0 GB');
      expect(formatBytes(1000000000000), '1.0 TB');
    });

    test("reproduces issue #28's reported figures", () {
      expect(formatBytes(852811776), '852.8 MB');
      expect(formatBytes(1101824), '1.1 MB');
    });

    test('stops at TB rather than inventing a unit', () {
      expect(formatBytes(5000000000000000), '5000.0 TB');
    });

    test('formats a negative delta, for a file that grew', () {
      // `sizeBefore - sizeAfter` can go negative: a VACUUM on an already
      // compact database can leave it marginally larger.
      expect(formatBytes(-1500), '-1.5 KB');
    });
  });
}
