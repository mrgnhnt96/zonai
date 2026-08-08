import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/update/update_simulator.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _Row {
  const _Row({
    this.id,
    required this.title,
    this.qty = 100,
    this.tags = const [],
  });

  final int? id;
  final String title;
  final int qty;
  final List<String> tags;
}

class _TestTable extends Table<_Row> {
  _TestTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      title = $.text('title', (s) => s.title),
      qty = $.integer('qty', (s) => s.qty),
      tags = $.list(
        'tags',
        (s) => s.tags,
        fromJson: (e) => switch (e) {
          String() => e,
          _ => '$e',
        },
      );

  @override
  _Row fromRow(RowReader read) => _Row(
    id: read(id),
    title: read(title)!,
    qty: read(qty)!,
    tags: read(tags)!,
  );

  final ColumnType<int?> id;
  final TextColumn title;
  final IntColumn qty;
  final ListColumn<String> tags;
}

final widgets = sqliteTable('sim_widgets', _TestTable.new);

final class _Operations extends TableOperations<_TestTable, _Row> {
  _Operations() : super(widgets);
}

class _JsonRow {
  const _JsonRow({
    this.id,
    required this.title,
    this.profile = const {},
    this.password = '',
  });

  final int? id;
  final String title;
  final Map<String, dynamic> profile;
  final String password;
}

class _JsonTable extends Table<_JsonRow> {
  _JsonTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      title = $.text('title', (s) => s.title),
      profile = $.map('profile', (s) => s.profile),
      password = $.password('password', (s) => s.password);

  @override
  _JsonRow fromRow(RowReader read) => _JsonRow(
    id: read(id),
    title: read(title)!,
    profile: read(profile)!,
    password: read(password) ?? '',
  );

  final ColumnType<int?> id;
  final TextColumn title;
  final MapColumn profile;
  final PasswordColumn password;
}

final jsonWidgets = sqliteTable('sim_json_widgets', _JsonTable.new);

final class _JsonOperations extends TableOperations<_JsonTable, _JsonRow> {
  _JsonOperations() : super(jsonWidgets);
}

/// Reads back the raw driver row (JSON columns as their stored TEXT string),
/// matching the shape `_updateOperation` sends over IPC as a rules-check row.
Future<Map<String, Object?>> _rawRow(
  Raindrop db,
  String table,
  String whereColumn,
  Object? whereValue,
) async {
  final result = await db.execute(
    'SELECT * FROM "$table" WHERE "$whereColumn" = ?',
    [whereValue],
  );
  final row = result.rows.single;
  return {
    for (var i = 0; i < result.columns.length; i++) result.columns[i]: row[i],
  };
}

void main() {
  final ops = _Operations();

  group('TableUpdateSimulation.simulateUpdate', () {
    test('NULL propagates through Increment like SQL arithmetic', () {
      final after = ops.table.simulateUpdate(
        {'id': 1, 'title': 't', 'qty': null, 'tags': '[]'},
        [Update.column('qty', const Increment())],
      );
      expect(after['qty'], isNull);
    });

    test('NULL propagates through Decrement like SQL arithmetic', () {
      final after = ops.table.simulateUpdate(
        {'id': 1, 'title': 't', 'qty': null, 'tags': '[]'},
        [Update.column('qty', const Decrement())],
      );
      expect(after['qty'], isNull);
    });

    test('no updates leaves the row untouched', () {
      final before = {'id': 1, 'title': 't', 'qty': 5, 'tags': '[]'};
      final after = ops.table.simulateUpdate(before, const []);
      expect(after, before);
    });

    group('SQLite execution parity', () {
      late Raindrop memoryDb;
      late _Operations execOps;

      setUp(() async {
        memoryDb = Raindrop(SQLiteDelegate(sqlite3.openInMemory()));
        execOps = _Operations()..db = memoryDb;
        await memoryDb.execute(
          'CREATE TABLE "sim_widgets" ('
          '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"title" TEXT NOT NULL, '
          '"qty" INTEGER NOT NULL DEFAULT 100, '
          '"tags" TEXT NOT NULL DEFAULT \'[]\''
          ');',
          const [],
        );
      });

      tearDown(() async {
        (memoryDb.delegate as SQLiteDelegate).dispose();
      });

      Future<void> expectSimulateMatchesReal(
        String title,
        List<Update> updates,
      ) async {
        final before = await _rawRow(memoryDb, 'sim_widgets', 'title', title);
        final simulatedAfter = execOps.table.simulateUpdate(before, updates);

        await execOps.update(updates, where: Eq('title', title));
        final realAfter = await _rawRow(
          memoryDb,
          'sim_widgets',
          'title',
          title,
        );

        expect(
          execOps.table.create(simulatedAfter),
          _matchesRow(execOps.table.create(realAfter)),
        );
      }

      test('Literal matches real UPDATE', () async {
        await execOps.insert({'title': 'lit', 'qty': 1, 'tags': '[]'});
        await expectSimulateMatchesReal('lit', [
          Update.column('qty', const Literal(42)),
        ]);
      });

      test('Increment matches real UPDATE', () async {
        await execOps.insert({'title': 'inc', 'qty': 10, 'tags': '[]'});
        await expectSimulateMatchesReal('inc', [
          Update.column('qty', const Increment()),
        ]);
      });

      test('Decrement matches real UPDATE', () async {
        await execOps.insert({'title': 'dec', 'qty': 10, 'tags': '[]'});
        await expectSimulateMatchesReal('dec', [
          Update.column('qty', const Decrement()),
        ]);
      });

      test('Add (arithmetic) matches real UPDATE', () async {
        await execOps.insert({'title': 'add-num', 'qty': 10, 'tags': '[]'});
        await expectSimulateMatchesReal('add-num', [
          Update.column('qty', const Add(7)),
        ]);
      });

      test('Remove (arithmetic) matches real UPDATE', () async {
        await execOps.insert({'title': 'rem-num', 'qty': 10, 'tags': '[]'});
        await expectSimulateMatchesReal('rem-num', [
          Update.column('qty', const Remove(3)),
        ]);
      });

      test('Add on a JSON list column matches real UPDATE — the exact '
          'privilege-escalation case from issue #23: a rule reading '
          '`after.tags` must see the appended value, not a stale copy of '
          '`before`', () async {
        await execOps.insert({
          'title': 'add-admin',
          'qty': 1,
          'tags': '["member"]',
        });
        final before = await _rawRow(
          memoryDb,
          'sim_widgets',
          'title',
          'add-admin',
        );
        final simulatedAfter = execOps.table.simulateUpdate(before, [
          Update.column('tags', const Add('admin')),
        ]);
        final simulatedRow = execOps.table.create(simulatedAfter);
        expect(simulatedRow.tags, contains('admin'));

        await expectSimulateMatchesReal('add-admin', [
          Update.column('tags', const Add('admin')),
        ]);
      });

      test('Remove on a JSON list column matches real UPDATE', () async {
        await execOps.insert({
          'title': 'rem-list',
          'qty': 1,
          'tags': '["a","b","a"]',
        });
        await expectSimulateMatchesReal('rem-list', [
          Update.column('tags', const Remove('a')),
        ]);
      });

      test('AddAll matches real UPDATE', () async {
        await execOps.insert({'title': 'add-all', 'qty': 1, 'tags': '["a"]'});
        await expectSimulateMatchesReal('add-all', [
          Update.column('tags', const AddAll(['b', 'c'])),
        ]);
      });

      test('RemoveAll matches real UPDATE', () async {
        await execOps.insert({
          'title': 'rem-all',
          'qty': 1,
          'tags': '["a","b","c","a"]',
        });
        await expectSimulateMatchesReal('rem-all', [
          Update.column('tags', const RemoveAll(['a', 'c'])),
        ]);
      });
    });

    group('jsonMap SQLite execution parity', () {
      late Raindrop memoryDb;
      late _JsonOperations execOps;

      setUp(() async {
        memoryDb = Raindrop(SQLiteDelegate(sqlite3.openInMemory()));
        execOps = _JsonOperations()..db = memoryDb;
        await memoryDb.execute(
          'CREATE TABLE "sim_json_widgets" ('
          '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"title" TEXT NOT NULL, '
          '"profile" TEXT NOT NULL DEFAULT \'{}\', '
          '"password" TEXT NOT NULL DEFAULT \'\''
          ');',
          const [],
        );
      });

      tearDown(() async {
        (memoryDb.delegate as SQLiteDelegate).dispose();
      });

      Future<void> expectSimulateMatchesReal(
        String title,
        List<Update> updates,
      ) async {
        final before = await _rawRow(
          memoryDb,
          'sim_json_widgets',
          'title',
          title,
        );
        final simulatedAfter = execOps.table.simulateUpdate(before, updates);

        await execOps.update(updates, where: Eq('title', title));
        final realAfter = await _rawRow(
          memoryDb,
          'sim_json_widgets',
          'title',
          title,
        );

        expect(
          execOps.table.create(simulatedAfter),
          _matchesJsonRow(execOps.table.create(realAfter)),
        );
      }

      test('dotted-path Literal set matches real UPDATE', () async {
        await execOps.insert({
          'title': 'dot1',
          'profile': {'displayName': 'Old', 'role': 'user'},
        });
        await expectSimulateMatchesReal('dot1', [
          Update.column('profile.displayName', const Literal('New')),
        ]);
      });

      test('dotted-path Literal set through a missing intermediate object '
          'matches real UPDATE (json_set creating nested objects)', () async {
        await execOps.insert({
          'title': 'dot2',
          'profile': {'displayName': 'Old'},
        });
        await expectSimulateMatchesReal('dot2', [
          Update.column('profile.contact.email', const Literal('a@b.com')),
        ]);
      });

      test('ObjectUpdate plain-map merge matches real UPDATE', () async {
        await execOps.insert({
          'title': 'merge1',
          'profile': {'displayName': 'Old', 'role': 'user'},
        });
        await expectSimulateMatchesReal('merge1', [
          Update.object({
            'profile': {'displayName': 'Merged'},
          }),
        ]);
      });

      test('ObjectUpdate merge with an explicit null deletes the key, matching '
          'RFC 7396 / real json_patch', () async {
        await execOps.insert({
          'title': 'merge2',
          'profile': {'displayName': 'Old', 'role': 'user'},
        });
        await expectSimulateMatchesReal('merge2', [
          Update.object({
            'profile': {'role': null},
          }),
        ]);
      });

      test('ObjectUpdate merge patch into a key absent from the target drops '
          'nulls, matching RFC 7396 / real json_patch', () async {
        await execOps.insert({
          'title': 'merge3',
          'profile': {'displayName': 'Old'},
        });
        await expectSimulateMatchesReal('merge3', [
          Update.object({
            'profile': {
              'nested': {'b': null, 'c': 2},
            },
          }),
        ]);
      });

      test('ObjectUpdate merge patch into a key holding a scalar drops nulls, '
          'matching RFC 7396 / real json_patch', () async {
        await execOps.insert({
          'title': 'merge4',
          'profile': {'a': 'scalar-value'},
        });
        await expectSimulateMatchesReal('merge4', [
          Update.object({
            'profile': {
              'a': {'b': null, 'c': 2},
            },
          }),
        ]);
      });

      test('ColumnUpdate without dots replaces the entire map', () async {
        await execOps.insert({
          'title': 'replace1',
          'profile': {'a': 1},
        });
        await expectSimulateMatchesReal('replace1', [
          Update.column('profile', const Literal({'b': 2})),
        ]);
      });

      group('secret column redaction', () {
        // Deliberately NOT run through expectSimulateMatchesReal: the real
        // UPDATE (no hashing at this layer) genuinely writes the submitted
        // plaintext, so simulated and real are expected to diverge here —
        // that divergence is the point, not a parity bug.
        test('a Literal password update is redacted in the simulated after '
            'row, never exposing the submitted plaintext', () async {
          await execOps.insert({
            'title': 'pw1',
            'profile': {},
            'password': 'old-hash',
          });
          final before = await _rawRow(
            memoryDb,
            'sim_json_widgets',
            'title',
            'pw1',
          );
          final after = execOps.table.simulateUpdate(before, [
            Update.column('password', const Literal('new-plaintext-password')),
          ]);
          expect(after['password'], '__REDACTED__');
        });

        test('an ObjectUpdate password update is redacted in the simulated '
            'after row, matching how the admin edit flow sends it', () async {
          await execOps.insert({
            'title': 'pw2',
            'profile': {},
            'password': 'old-hash',
          });
          final before = await _rawRow(
            memoryDb,
            'sim_json_widgets',
            'title',
            'pw2',
          );
          final after = execOps.table.simulateUpdate(before, [
            Update.object({'password': 'new-plaintext-password'}),
          ]);
          expect(after['password'], '__REDACTED__');
        });
      });
    });
  });
}

Matcher _matchesRow(_Row expected) {
  return isA<_Row>()
      .having((r) => r.id, 'id', expected.id)
      .having((r) => r.title, 'title', expected.title)
      .having((r) => r.qty, 'qty', expected.qty)
      .having((r) => r.tags, 'tags', expected.tags);
}

Matcher _matchesJsonRow(_JsonRow expected) {
  return isA<_JsonRow>()
      .having((r) => r.id, 'id', expected.id)
      .having((r) => r.title, 'title', expected.title)
      .having((r) => r.profile, 'profile', expected.profile);
}
