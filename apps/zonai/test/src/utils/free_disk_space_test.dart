import 'package:test/test.dart';
import 'package:zonai/src/utils/free_disk_space.dart';

/// The `df -Pk` parsing, against real captured output.
///
/// Worth its own test because the caller cannot check it: a wrong number here
/// does not fail, it just gates a `VACUUM` on a fiction. And the two ways it
/// goes wrong are both invisible -- reading the Used column instead of
/// Available (off by the size of the data), or losing a column to a wrapped
/// line (off by a whole field).
void main() {
  group('parseDfAvailableBytes', () {
    test('reads the Available column, in bytes', () {
      // macOS, `df -Pk /`.
      const output = '''
Filesystem 1024-blocks      Used Available Capacity  Mounted on
/dev/disk3s1s1  971350180  10485760 500000000     3%    /
''';
      expect(parseDfAvailableBytes(output), 500000000 * 1024);
    });

    test('handles a mount point containing spaces', () {
      const output = '''
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk4s1  1000000  400000    600000    40% /Volumes/My Disk
''';
      expect(parseDfAvailableBytes(output), 600000 * 1024);
    });

    test('reads a Linux long-device-name line, which -P keeps unwrapped', () {
      // The reason the call passes `-P`: without it, `df` wraps a device name
      // this long onto its own line and every column shifts down one, so a
      // naive parse silently returns the *Used* column.
      const output = '''
Filesystem     1024-blocks    Used Available Capacity Mounted on
/dev/mapper/vg--fly--0--vol-fly_fly--0--vol 999320 913044 33436 97% /data
''';
      expect(parseDfAvailableBytes(output), 33436 * 1024);
    });

    test('returns null rather than a number it cannot stand behind', () {
      // `null` means unknown, and the caller treats unknown as "go ahead and
      // let the write decide". Returning 0 here would instead read as "the
      // disk is full" and refuse to ever reclaim anything.
      expect(parseDfAvailableBytes(''), isNull);
      expect(parseDfAvailableBytes('Filesystem 1024-blocks Used\n'), isNull);
      expect(
        parseDfAvailableBytes(
          'Filesystem 1024-blocks Used Available Cap On\n'
          'df: /nope: No such file or directory\n',
        ),
        isNull,
      );
    });
  });
}
