import 'package:test/test.dart';
import 'package:zonai_web/providers/maintenance_provider.dart';

/// The distinction the whole storage panel rests on.
///
/// `freeDiskBytes` returns `null` for *unknown* and never zero, and its own
/// doc comment is explicit that an unparsed `df` and a full disk are opposite
/// situations. A UI that collapses the first into "0 B free" reports an
/// emergency that is not happening — and, worse, hides that it never read the
/// value, so an operator hunting for space is sent to fix the wrong thing.
void main() {
  group('formatOptionalBytes', () {
    test('renders an unknown size as a word, not as zero', () {
      expect(formatOptionalBytes(null), 'unknown');
      expect(
        formatOptionalBytes(null),
        isNot(contains('0')),
        reason: 'an unreadable `df` must never render as a byte count, of any size',
      );
    });

    test('a genuine zero is still zero, and is not the unknown text', () {
      expect(
        formatOptionalBytes(0),
        '0 B',
        reason: 'a truly full volume is a real reading and has to survive the round trip distinguishable from null',
      );
      expect(formatOptionalBytes(0), isNot(kUnknownSize));
    });

    test('a known size formats as the engine formats it', () {
      // Same decimal units the engine logs with, so a size shown here lines up
      // with the one in the log an operator is reading beside it.
      expect(formatOptionalBytes(852811776), '852.8 MB');
      expect(formatOptionalBytes(1000), '1.0 KB');
    });
  });
}
