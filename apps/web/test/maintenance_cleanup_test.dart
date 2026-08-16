import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/providers/maintenance_provider.dart';

/// What the Cleanup section tells an operator after it has acted.
///
/// The engine's return values are the interesting part of every one of these
/// verbs, and the failure mode this guards against is a UI that throws them
/// away and says "Done". A purge that removed 4.6M rows and one that matched
/// nothing both succeed; a reclaim that rewrote 2 GB and one that could not
/// rewrite anything because the volume is full both return without error.
void main() {
  group('purge dropdown', () {
    test('_photos is not offered', () {
      // Deleting a photo row also deletes the file behind it, through a
      // per-row path a bulk DELETE has no hook for. Offering `_photos` here
      // would let an operator orphan every file the purge removed a row for.
      expect(
        purgeableTableOptions(),
        isNot(contains('_photos')),
        reason:
            'photos are cleaned by the unreferenced-photo sweep, one row at a '
            'time, precisely because a bulk purge cannot delete their files',
      );
    });

    test('the internal tables that are safe to purge are offered', () {
      // The other half of the claim: a dropdown that drifted to empty would
      // pass the test above for the wrong reason.
      final options = purgeableTableOptions();
      expect(options, contains('_log'));
      expect(options, contains('_jwt'));
      expect(options, contains('_rate_limit'));
    });

    test('the order is stable', () {
      // Rebuilt on every render; an unordered set would reshuffle the dropdown
      // under an operator's cursor.
      expect(purgeableTableOptions(), orderedEquals(purgeableTableOptions()));
      expect(purgeableTableOptions(), orderedEquals([...purgeableTableOptions()]..sort()));
    });
  });

  group('describeReclamation', () {
    test('surfaces the skip reason verbatim', () {
      const reason = 'not enough free disk for the rewrite';
      final outcome = describeReclamation(
        const LogSpaceReclamationResult(
          reclaimableBytes: 32 * 1024 * 1024,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: reason,
        ),
      );

      // Verbatim, not paraphrased and not collapsed to a boolean: this string
      // is the only thing separating "the volume is full, go extend it" from
      // "there was nothing to reclaim".
      expect(outcome.text, contains(reason));
      expect(outcome.isSkip, isTrue);
    });

    test('a skip is distinguishable from having nothing to reclaim', () {
      final skipped = describeReclamation(
        const LogSpaceReclamationResult(
          reclaimableBytes: 32 * 1024 * 1024,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: 'not enough free disk for the rewrite',
        ),
      );
      final nothingToDo = describeReclamation(
        const LogSpaceReclamationResult(
          reclaimableBytes: 1024,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: null,
        ),
      );

      // Both reclaimed zero bytes and neither threw. This is the exact pair
      // the `skipped` field exists to tell apart, so the two must not render
      // as the same sentence.
      expect(skipped.text, isNot(nothingToDo.text));
      expect(skipped.isSkip, isTrue);
      expect(nothingToDo.isSkip, isFalse);
    });

    test('a skip still reports what is sitting on the freelist', () {
      final outcome = describeReclamation(
        const LogSpaceReclamationResult(
          reclaimableBytes: 2 * 1000 * 1000 * 1000,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: 'not enough free disk for the rewrite',
        ),
      );

      // "0 B reclaimed" on its own reads as "nothing to do" in precisely the
      // situation where there are two gigabytes to recover and no room to do
      // it in.
      expect(outcome.text, contains('2.0 GB'));
    });

    test('a successful rewrite reports the bytes actually handed back', () {
      final outcome = describeReclamation(
        const LogSpaceReclamationResult(
          reclaimableBytes: 100 * 1000 * 1000,
          reclaimedBytes: 98 * 1000 * 1000,
          vacuumed: true,
          skipped: null,
        ),
      );

      expect(outcome.text, contains('98.0 MB'));
      expect(outcome.isSkip, isFalse);
    });
  });

  group('describeRowsPurged', () {
    test('a real count is exact', () {
      // "some rows" is not something an operator can compare against the row
      // total they were looking at a moment ago.
      expect(describeRowsPurged(4600000, noun: 'log rows'), contains('4600000'));
    });

    test('nothing matched is said as such, not as a count of zero', () {
      final text = describeRowsPurged(0, noun: 'log rows');
      expect(text, isNot(contains('0 ')));
      expect(text, contains('Nothing to delete'));
    });

    test('one row is singular', () {
      expect(describeRowsPurged(1, noun: 'log rows'), '1 log row deleted');
      expect(describeRowsPurged(1, noun: 'rows'), '1 row deleted');
    });
  });

  group('describePhotoCleanup', () {
    test('reports the count and that files went too', () {
      final text = describePhotoCleanup(3);
      expect(text, contains('3'));
      // The distinguishing property of this verb versus a purge.
      expect(text, contains('files'));
    });

    test('nothing unreferenced is not phrased as a failure', () {
      expect(describePhotoCleanup(0), contains('Nothing to delete'));
    });
  });

  group('cleanupConfirmMatches', () {
    test('accepts the phrase, ignoring case and surrounding space', () {
      expect(cleanupConfirmMatches(typed: '_jwt', expected: '_jwt'), isTrue);
      expect(cleanupConfirmMatches(typed: '  _JWT  ', expected: '_jwt'), isTrue);
    });

    test('refuses anything else, including empty and a near miss', () {
      expect(cleanupConfirmMatches(typed: '', expected: '_jwt'), isFalse);
      expect(cleanupConfirmMatches(typed: '_jw', expected: '_jwt'), isFalse);
      // The case the per-table phrase exists for: confirming one table must
      // not arm a purge of a different one.
      expect(cleanupConfirmMatches(typed: '_jwt', expected: '_log'), isFalse);
    });
  });
}
