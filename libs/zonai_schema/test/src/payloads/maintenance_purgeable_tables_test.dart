import 'package:test/test.dart';
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import 'package:zonai_schema/src/payloads/maintenance_actions.dart';

/// [kPurgeableTableNames] is a hand-written mirror of a derived set, so the
/// thing worth pinning is that it still mirrors it.
///
/// The engine derives its own `_purgeableTables` from
/// `InternalDbArtifacts.tableNames` precisely so a new internal table is
/// covered without anyone remembering. The UI copy cannot import that list —
/// it reaches Raindrop's column builders and native SQLite through it, and
/// `payloads.dart` is what `apps/web` compiles to JavaScript. This test is
/// what makes the copy safe: it is a VM test, so it can import both, and it
/// fails the moment the two disagree.
void main() {
  /// The engine's derivation, spelled exactly as `purge.dart` spells it.
  final engineSet = InternalDbArtifacts.tableNames.difference({'_photos'});

  test('the UI mirror equals the engine derivation', () {
    expect(
      kPurgeableTableNames,
      equals(engineSet),
      reason:
          'a new internal table was added (or removed) and the browser-safe '
          'copy in maintenance_actions.dart was not updated. Update '
          'kPurgeableTableNames to match InternalDbArtifacts.tableNames minus '
          '_photos.',
    );
  });

  test('_photos is not purgeable', () {
    // Not implied by the test above -- that one only pins the two sets to each
    // other, so both could drift to include `_photos` together. Deleting a
    // photo row also deletes the file behind it, via a per-row path a bulk
    // DELETE has no hook for, so a purge would orphan every file it removed a
    // row for. `_cleanup_unreferenced_photos` is the verb for photos.
    expect(kPurgeableTableNames, isNot(contains('_photos')));
    expect(engineSet, isNot(contains('_photos')));
  });

  test('the set is not empty, and does contain the table this exists for', () {
    // A mirror that drifted to empty would satisfy "does not contain _photos"
    // for the wrong reason, and would quietly leave the dropdown blank.
    expect(kPurgeableTableNames, contains('_log'));
    expect(kPurgeableTableNames.length, greaterThan(1));
  });

  /// `ZonaiDb.purge` has no "match everything" form — it requires a `Where` —
  /// so the maintenance endpoint synthesises `NotNull('id')` to empty a table.
  ///
  /// That is only safe while every purgeable table really has an `id` column.
  /// The operations layer validates column names against these same generated
  /// schemas, so a table without one would fail at the SQL layer, on that
  /// table alone, the first time an operator picked it out of the dropdown.
  /// `rowid` is the tempting alternative and is the wrong answer — it is in no
  /// generated schema at all.
  test(
    'every purgeable table has the `id` column the endpoint predicates on',
    () {
      final columnsByTable = {
        for (final schema in InternalDbArtifacts.schemas)
          schema.$.name: schema.$.columns.map((c) => c.name).toSet(),
      };

      // A typo'd or renamed table would otherwise make the loop below vacuous.
      expect(
        columnsByTable.keys,
        containsAll(kPurgeableTableNames),
        reason: 'every purgeable table must have a schema to check',
      );

      for (final table in kPurgeableTableNames) {
        expect(
          columnsByTable[table],
          contains('id'),
          reason:
              '$table is offered in the purge dropdown, and the endpoint empties '
              'it with NotNull("id")',
        );
      }
    },
  );
}
