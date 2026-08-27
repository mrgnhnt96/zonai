import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/providers/maintenance_provider.dart';

/// A storage report with the three files a real deployment has, in the order
/// the endpoint builds them: application database first.
StorageMetrics _storageReport({int mainReclaimable = 9_500_000, String mainName = 'zonai.sqlite'}) {
  return StorageMetrics(
    databases: [
      StorageDatabaseFile(
        name: mainName,
        path: '/data/$mainName',
        schema: 'main',
        sizeBytes: 40_000_000,
        walBytes: 0,
        reclaimableBytes: mainReclaimable,
      ),
      const StorageDatabaseFile(
        name: 'zonai_log.sqlite',
        path: '/data/zonai_log.sqlite',
        schema: 'logdb',
        sizeBytes: 20_520,
        walBytes: 288_000,
        reclaimableBytes: 28_000,
      ),
      const StorageDatabaseFile(
        name: 'zonai_rate.sqlite',
        path: '/data/zonai_rate.sqlite',
        schema: 'ratedb',
        sizeBytes: 8_192,
        walBytes: 0,
        reclaimableBytes: null,
      ),
    ],
    photosBytes: 0,
    photosFileCount: 0,
    tables: const [],
  );
}

/// The [ReclaimTarget] for [schema] in a default report.
ReclaimTarget _target(String schema, {StorageMetrics? from}) {
  return reclaimTargetOptions(from ?? _storageReport()).firstWhere((t) => t.schema == schema);
}

/// What the Cleanup section tells an operator after it has acted.
///
/// The engine's return values are the interesting part of every one of these
/// verbs, and the failure mode this guards against is a UI that throws them
/// away and says "Done". A purge that removed 4.6M rows and one that matched
/// nothing both succeed; a reclaim that rewrote 2 GB and one that could not
/// rewrite anything because the volume is full both return without error.
///
/// The reclaim half of it also has to answer *which* database it acted on,
/// now that the card picks a target rather than always meaning the log file.
void main() {
  group('reclaim dropdown', () {
    test('is built from the storage report, not from a hardcoded list', () {
      // The point of the whole change: the card offers the files this
      // deployment actually has, with this deployment's numbers.
      final options = reclaimTargetOptions(_storageReport(mainName: 'custom.sqlite'));

      expect(options.map((t) => t.schema), ['main', 'logdb', 'ratedb']);
      expect(options.first.name, 'custom.sqlite');
      expect(options.first.sizeBytes, 40_000_000);
      expect(options.first.reclaimableBytes, 9_500_000);
    });

    test('is empty before the report arrives', () {
      // Not a list of guesses. There is nothing to aim at yet, and the card
      // says so rather than offering a file it has not measured.
      expect(reclaimTargetOptions(null), isEmpty);
    });

    test('the order is stable, and is the report order', () {
      final report = _storageReport();
      expect(
        reclaimTargetOptions(report).map((t) => t.schema),
        orderedEquals(reclaimTargetOptions(report).map((t) => t.schema)),
        reason: 'rebuilt on every render; a reshuffle would move the dropdown under the cursor',
      );
      expect(
        reclaimTargetOptions(report).map((t) => t.schema),
        orderedEquals(report.databases.map((d) => d.schema)),
        reason: 'same order as the Database files panel above it on the same screen',
      );
    });

    test('the value is the schema, never the file name or the path', () {
      // A path is an operator-configurable string arriving from a browser; a
      // schema is one of three values the engine attaches by.
      for (final target in reclaimTargetOptions(_storageReport())) {
        expect(kReclaimableSchemas, contains(target.schema));
        expect(target.schema, isNot(contains('/')));
        expect(target.schema, isNot(contains('.sqlite')));
      }
    });

    test('the label names the file and what is reclaimable in it', () {
      // Three bare file names would ask the operator to already know which
      // one has dead space in it.
      expect(_target('main').label, contains('zonai.sqlite'));
      expect(_target('main').label, contains('9.5 MB'));
    });

    test('an unreadable freelist is labelled unknown, not zero', () {
      // `null` reclaimable is "the pragmas could not be read", which is the
      // opposite of "there is nothing to recover here".
      expect(_target('ratedb').label, contains(kUnknownSize));
      expect(_target('ratedb').label, isNot(contains('0 B')));
    });

    test('a schema the server would refuse is not offered', () {
      // An option guaranteed to come back as a rejection is worse than no
      // option. The server validates against the same set.
      final report = StorageMetrics(
        databases: const [
          StorageDatabaseFile(
            name: 'somewhere_else.sqlite',
            path: '/data/somewhere_else.sqlite',
            schema: 'attachedb',
            sizeBytes: 1024,
            walBytes: 0,
            reclaimableBytes: 0,
          ),
        ],
        photosBytes: 0,
        photosFileCount: 0,
        tables: const [],
      );

      expect(reclaimTargetOptions(report), isEmpty);
    });
  });

  group('reclaimConfirmPhrase', () {
    test('main demands the file\'s own name typed', () {
      // A VACUUM on the application database takes an exclusive lock on
      // application data: every write blocks for its duration. That is an
      // outage, and it is not something to press once.
      expect(reclaimConfirmPhrase(_target('main')), 'zonai.sqlite');
      expect(
        reclaimConfirmPhrase(_target('main', from: _storageReport(mainName: 'renamed.sqlite'))),
        'renamed.sqlite',
        reason: 'the phrase is the file the report named, not a hardcoded one',
      );
    });

    test('logdb and ratedb need nothing typed, as before', () {
      // Still not destructive, and still a file of its own -- the original
      // justification survives for exactly these targets. A typed confirm on
      // a harmless verb trains an operator to type through the ones that
      // matter.
      expect(reclaimConfirmPhrase(_target('logdb')), isNull);
      expect(reclaimConfirmPhrase(_target('ratedb')), isNull);
    });

    test('there is nothing to confirm before a target exists', () {
      expect(reclaimConfirmPhrase(null), isNull);
    });

    test('a phrase typed for one target does not arm another', () {
      // The property the per-target phrase exists for, checked through the
      // matcher the card actually uses.
      final phrase = reclaimConfirmPhrase(_target('main'))!;
      expect(cleanupConfirmMatches(typed: phrase, expected: phrase), isTrue);
      expect(cleanupConfirmMatches(typed: 'zonai_log.sqlite', expected: phrase), isFalse);
    });
  });

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
        const SpaceReclamationResult(
          target: 'logdb',
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
        const SpaceReclamationResult(
          target: 'logdb',
          reclaimableBytes: 32 * 1024 * 1024,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: 'not enough free disk for the rewrite',
        ),
      );
      final nothingToDo = describeReclamation(
        const SpaceReclamationResult(
          target: 'logdb',
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
        const SpaceReclamationResult(
          target: 'logdb',
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
        const SpaceReclamationResult(
          target: 'logdb',
          reclaimableBytes: 100 * 1000 * 1000,
          reclaimedBytes: 98 * 1000 * 1000,
          vacuumed: true,
          skipped: null,
        ),
      );

      expect(outcome.text, contains('98.0 MB'));
      expect(outcome.isSkip, isFalse);
    });

    test('every outcome names the database it is about', () {
      // A result stays on screen after it lands, and the operator can move the
      // picker while it is still there. Without the target, a report about the
      // log database reads as a report about whatever is now selected.
      const base = SpaceReclamationResult(
        target: 'main',
        reclaimableBytes: 9_500_000,
        reclaimedBytes: 0,
        vacuumed: false,
        skipped: null,
      );

      final skipped = describeReclamation(
        const SpaceReclamationResult(
          target: 'main',
          reclaimableBytes: 9_500_000,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: 'not enough free disk for the rewrite',
        ),
      );
      final rewritten = describeReclamation(
        const SpaceReclamationResult(
          target: 'main',
          reclaimableBytes: 9_500_000,
          reclaimedBytes: 9_000_000,
          vacuumed: true,
          skipped: null,
        ),
      );

      for (final outcome in [describeReclamation(base), skipped, rewritten]) {
        expect(outcome.text, contains('application database'));
      }
    });

    test('the target it names is the result\'s, not the picker\'s', () {
      // Same numbers, different target: the sentences must differ, because
      // that is the whole reason `target` rides on the payload.
      final fromLog = describeReclamation(
        const SpaceReclamationResult(
          target: 'logdb',
          reclaimableBytes: 1024,
          reclaimedBytes: 1024,
          vacuumed: true,
          skipped: null,
        ),
      );
      final fromMain = describeReclamation(
        const SpaceReclamationResult(
          target: 'main',
          reclaimableBytes: 1024,
          reclaimedBytes: 1024,
          vacuumed: true,
          skipped: null,
        ),
      );

      expect(fromLog.text, isNot(fromMain.text));
      expect(fromLog.text, contains('log database'));
      expect(fromMain.text, contains('application database'));
    });

    test('every reclaimable schema has a phrase of its own', () {
      // The set is written out in two places (here and the engine), so drift
      // is what a test has to pin. An unrecognised schema falls back to a
      // quoted identifier; no member of the set may land on it.
      for (final schema in kReclaimableSchemas) {
        expect(
          reclaimTargetLabel(schema),
          isNot(contains('"')),
          reason: '$schema fell through to the unrecognised-identifier fallback',
        );
      }
    });

    test('an unrecognised target is still named rather than dropped', () {
      // A failed lookup must not silently become "some database". The
      // identifier is the only thing saying which file the numbers are about.
      final outcome = describeReclamation(
        const SpaceReclamationResult(
          target: 'attachedb',
          reclaimableBytes: 1024,
          reclaimedBytes: 0,
          vacuumed: true,
          skipped: null,
        ),
      );

      expect(outcome.text, contains('attachedb'));
    });

    test('the nothing-to-do sentence does not promise a fixed threshold', () {
      // The screen sends a floor of zero, so the engine's `reclaimable < floor`
      // test can never take this branch from the card. The old wording said
      // the freelist was "under the threshold for a rewrite", which is not a
      // true thing to say when the threshold is zero.
      expect(kUiReclaimFloorBytes, 0);

      final outcome = describeReclamation(
        const SpaceReclamationResult(
          target: 'logdb',
          reclaimableBytes: 1024,
          reclaimedBytes: 0,
          vacuumed: false,
          skipped: null,
        ),
      );

      expect(outcome.text, isNot(contains('the threshold')));
      expect(outcome.text, contains('the floor this run asked for'));
      expect(outcome.isSkip, isFalse);
    });
  });

  group('describeReclaimLock', () {
    // For `logdb` and `ratedb` this string is still the entire disclosure --
    // they carry no typed confirmation. These pin the properties that make it
    // one, and that it tells the truth about whichever file is selected.
    test('the lock is the first thing said, not the last', () {
      final text = describeReclaimLock(_target('logdb'));

      expect(
        text.indexOf('Locks'),
        lessThan(text.indexOf('not touched')),
        reason: 'reassurance read first is what makes a warning read last',
      );
      expect(
        text.toLowerCase().indexOf('lock'),
        lessThan(20),
        reason: 'the stall has to be in the first clause, not the third sentence',
      );
    });

    test('the lock still leads for main, whose closing clause is a warning', () {
      final text = describeReclaimLock(_target('main'));

      expect(text.toLowerCase().indexOf('lock'), lessThan(20));
      expect(
        text.indexOf('Locks'),
        lessThan(text.indexOf('every write to it waits')),
        reason: 'the consequence that cannot be undone by waiting goes first',
      );
    });

    test('names application writes for main and log writes for logdb', () {
      // The clause that was false the moment this card stopped being
      // log-only. A VACUUM on the application database blocks application
      // writes; saying "log writes" there is simply wrong.
      final mainText = describeReclaimLock(_target('main'));
      final logText = describeReclaimLock(_target('logdb'));

      expect(mainText, contains('application writes block'));
      expect(mainText, isNot(contains('log writes')));
      expect(logText, contains('log writes block'));
      expect(logText, isNot(contains('application writes block')));
    });

    test('every reclaimable schema names its own writes', () {
      // The vague fallback is for a schema the server would refuse anyway. No
      // member of the set may quietly land on it.
      for (final schema in kReclaimableSchemas) {
        expect(
          reclaimBlockedWrites(schema),
          isNot('writes to that database'),
          reason: '$schema fell through to the vague fallback clause',
        );
      }
    });

    test('only the non-application targets promise the application is safe', () {
      // "The application database is not touched" does not survive
      // generalisation: it is the one claim that is false for `main`.
      expect(describeReclaimLock(_target('logdb')), contains('application database is not touched'));
      expect(describeReclaimLock(_target('ratedb')), contains('application database is not touched'));
      expect(describeReclaimLock(_target('main')), isNot(contains('is not touched')));
    });

    test('every target promises no rows are deleted', () {
      // True of all three: a rewrite moves no rows, it closes the gaps the
      // already-deleted ones left.
      for (final target in reclaimTargetOptions(_storageReport())) {
        expect(describeReclaimLock(target), contains('No rows are deleted'));
      }
    });

    test('carries the size, because the stall scales with it', () {
      final report = _storageReport();
      final big = reclaimTargetOptions(report).first;

      expect(
        describeReclaimLock(big),
        contains('40.0 MB'),
        reason: 'locking 20 KB and locking 40 MB are opposite decisions',
      );
      expect(describeReclaimLock(_target('logdb')), contains('20.5 KB'));
    });

    test('names the file the report gave, not a hardcoded one', () {
      // A deployment that renamed a database must not be told the reclaim
      // locks a file that does not exist there.
      final renamed = _target('main', from: _storageReport(mainName: 'custom.sqlite'));
      expect(describeReclaimLock(renamed), contains('custom.sqlite'));
    });

    test('before the report there is no file named and no unknown size', () {
      // Reads correctly rather than emptily: it says what the verb does and
      // what it costs, both of which are true of every target, and stops.
      final text = describeReclaimLock(null);

      expect(text, isNot(contains(kUnknownSize)));
      expect(text, isNot(contains('()')));
      expect(text, isNot(contains('.sqlite')));
      expect(text, contains('Locks the file it rewrites'));
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
