import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:zonai_sync/zonai_sync.dart';
import 'package:zonai_sync_drift/zonai_sync_drift.dart';

// The in-memory zonai fake lives with the engine's own tests.
// ignore: avoid_relative_lib_imports
import '../../zonai_sync/test/support/fake_zonai.dart';

/// A database with no generated tables: the app's synced table is plain SQL
/// here so the store is tested without codegen.
final class TestDb extends GeneratedDatabase {
  TestDb() : super(NativeDatabase.memory());

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

/// A [DriftSyncTable] over `notes(id TEXT PRIMARY KEY, data TEXT)`.
final class NotesTable implements DriftSyncTable {
  NotesTable(this.db);

  final GeneratedDatabase db;

  Future<void> create() => db.customStatement(
    'CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
  );

  @override
  String get name => 'notes';

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final row = await db
        .customSelect(
          'SELECT data FROM notes WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return (jsonDecode(row.read<String>('data')) as Map)
        .cast<String, Object?>();
  }

  @override
  Future<void> write(Map<String, Object?> wire) => db.customStatement(
    'INSERT INTO notes (id, data) VALUES (?, ?) '
    'ON CONFLICT (id) DO UPDATE SET data = excluded.data',
    [wire['id'], jsonEncode(wire)],
  );

  @override
  Future<void> delete(String id) =>
      db.customStatement('DELETE FROM notes WHERE id = ?', [id]);

  @override
  Future<List<String>> ids() async => [
    for (final r in await db.customSelect('SELECT id FROM notes').get())
      r.read<String>('id'),
  ];

  @override
  Future<void> clear() => db.customStatement('DELETE FROM notes');

  Future<int> count() async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM notes').getSingle())
          .read<int>('n');
}

void main() {
  late TestDb db;
  late NotesTable notes;
  late DriftSyncStore store;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = TestDb();
    notes = NotesTable(db);
    await notes.create();
    store = await DriftSyncStore.open(db, [notes]);
  });

  tearDown(() => db.close());

  group('SyncLocalStore contract', () {
    test(
      'rows: write, read, delete — base revision tracked separately',
      () async {
        await store.writeRow('notes', {'id': 'a', 'body': 'x'});
        var row = await store.readRow('notes', 'a');
        expect(row!.data['body'], 'x');
        expect(row.baseRev, isNull, reason: 'never on the server');

        await store.setBaseRev('notes', 'a', 4);
        await store.writeRow('notes', {'id': 'a', 'body': 'y'});
        row = await store.readRow('notes', 'a');
        expect(row!.data['body'], 'y');
        expect(row.baseRev, 4, reason: 'a local edit keeps its base');

        await store.deleteRow('notes', 'a');
        expect(await store.readRow('notes', 'a'), isNull);
        await store.writeRow('notes', {'id': 'a'});
        expect(
          (await store.readRow('notes', 'a'))!.baseRev,
          isNull,
          reason: 'deleting a row forgets its base',
        );
      },
    );

    test('applyRemote stores data + base; a tombstone deletes', () async {
      await store.applyRemote(
        'notes',
        const RemoteRow({
          'id': 'a',
          'rev': 3,
          'updated_at': 10,
          'deleted_at': null,
        }),
      );
      expect((await store.readRow('notes', 'a'))!.baseRev, 3);
      await store.applyRemote(
        'notes',
        const RemoteRow({
          'id': 'a',
          'rev': 4,
          'updated_at': 11,
          'deleted_at': 11,
        }),
      );
      expect(await store.readRow('notes', 'a'), isNull);
    });

    test('outbox: put, find, update in place, remove, list in order', () async {
      final ids = [for (var i = 0; i < 3; i++) await store.nextOutboxId()];
      expect(ids, [1, 2, 3]);
      OutboxEntry entry(int id, String row) => OutboxEntry(
        id: id,
        table: 'notes',
        rowId: row,
        op: OutboxOp.upsert,
        payload: {'id': row},
        changedFields: const {'id'},
        baseRev: null,
        version: 1,
      );
      await store.putEntry(entry(2, 'b'));
      await store.putEntry(entry(1, 'a'));
      expect((await store.entries()).map((e) => e.id), [1, 2]);
      expect((await store.pendingFor('notes', 'b'))!.id, 2);
      await store.putEntry(entry(2, 'b').copyWith(version: 5));
      expect((await store.entry(2))!.version, 5);
      await store.removeEntry(2);
      expect(await store.pendingFor('notes', 'b'), isNull);
    });

    test(
      'outbox ids never repeat, even after the newest entry is removed',
      () async {
        final first = await store.nextOutboxId();
        await store.removeEntry(first);
        expect(await store.nextOutboxId(), greaterThan(first));
      },
    );

    test('rowIds lists the table', () async {
      await store.writeRow('notes', {'id': 'a'});
      await store.writeRow('notes', {'id': 'b'});
      expect(await store.rowIds('notes'), unorderedEquals(['a', 'b']));
    });

    test('cursor and account round-trip', () async {
      const cursor = SyncCursor(updatedAt: 99, id: 'z', seq: 7);
      await store.setCursor('notes', cursor);
      expect(await store.cursor('notes'), cursor);
      expect(await store.account(), isNull);
      await store.setAccount('u1');
      expect(await store.account(), 'u1');
    });

    test('clearAll wipes rows, outbox, cursors and bases', () async {
      await store.applyRemote(
        'notes',
        const RemoteRow({'id': 'a', 'rev': 1, 'updated_at': 1}),
      );
      await store.setCursor('notes', const SyncCursor(updatedAt: 1, id: 'a'));
      await store.putEntry(
        OutboxEntry(
          id: await store.nextOutboxId(),
          table: 'notes',
          rowId: 'a',
          op: OutboxOp.delete,
          payload: const {},
          changedFields: const {},
          baseRev: 1,
          version: 1,
        ),
      );
      await store.clearAll();
      expect(await notes.count(), 0);
      expect(await store.entries(), isEmpty);
      expect(await store.cursor('notes'), isNull);
      await store.writeRow('notes', {'id': 'a'});
      expect((await store.readRow('notes', 'a'))!.baseRev, isNull);
    });

    test('a transaction that throws leaves nothing behind', () async {
      await expectLater(
        store.transaction(() async {
          await store.writeRow('notes', {'id': 'a'});
          await store.putEntry(
            OutboxEntry(
              id: await store.nextOutboxId(),
              table: 'notes',
              rowId: 'a',
              op: OutboxOp.upsert,
              payload: const {'id': 'a'},
              changedFields: const {'id'},
              baseRev: null,
              version: 1,
            ),
          );
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(await store.readRow('notes', 'a'), isNull);
      expect(await store.entries(), isEmpty);
    });

    test('bookkeeping survives reopening the database', () async {
      await store.setAccount('u1');
      await store.setCursor('notes', const SyncCursor(updatedAt: 5, id: 'x'));
      final again = await DriftSyncStore.open(db, [notes]);
      expect(await again.account(), 'u1');
      expect((await again.cursor('notes'))!.updatedAt, 5);
    });
  });

  group('engine on drift', () {
    SyncEngine engine(FakeZonai server, DriftSyncStore s) => SyncEngine(
      remote: server,
      local: s,
      tables: const [SyncTable('notes')],
      account: () => 'u1',
      syncOnWrite: false,
    );

    test('a write reaches another device through the server', () async {
      final server = FakeZonai();
      final phone = engine(server, store);
      await phone.write('notes', {'id': 'n1', 'owner_id': 'u1', 'body': 'hi'});
      await phone.sync();

      final otherDb = TestDb();
      addTearDown(otherDb.close);
      final otherNotes = NotesTable(otherDb);
      await otherNotes.create();
      final tablet = engine(
        server,
        await DriftSyncStore.open(otherDb, [otherNotes]),
      );
      await tablet.sync();
      expect((await otherNotes.read('n1'))!['body'], 'hi');
    });

    test('concurrent edits to different fields both survive', () async {
      final server = FakeZonai();
      final a = engine(server, store);
      await a.write('notes', {'id': 'n1', 'owner_id': 'u1', 'x': 0, 'y': 0});
      await a.sync();

      final otherDb = TestDb();
      addTearDown(otherDb.close);
      final otherNotes = NotesTable(otherDb);
      await otherNotes.create();
      final bStore = await DriftSyncStore.open(otherDb, [otherNotes]);
      final b = engine(server, bStore);
      await b.sync();

      await a.write('notes', {...(await notes.read('n1'))!, 'x': 1});
      await b.write('notes', {...(await otherNotes.read('n1'))!, 'y': 2});
      await a.sync();
      await b.sync();
      await a.sync();
      expect((await notes.read('n1'))!, containsPair('x', 1));
      expect((await notes.read('n1'))!, containsPair('y', 2));
    });

    test('a different account never inherits the previous one', () async {
      final server = FakeZonai()..offline = true;
      var account = 'u1';
      final e = SyncEngine(
        remote: server,
        local: store,
        tables: const [SyncTable('notes')],
        account: () => account,
        syncOnWrite: false,
      );
      await e.write('notes', {'id': 'secret', 'owner_id': 'u1'});
      account = 'u2';
      server
        ..offline = false
        ..user = 'u2';
      await e.sync();
      expect(await notes.read('secret'), isNull);
      expect(server.calls.where((c) => c.contains('secret')), isEmpty);
    });
  });
}
