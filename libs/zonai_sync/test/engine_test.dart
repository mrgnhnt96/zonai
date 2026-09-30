import 'package:test/test.dart';
import 'package:zonai_sync/zonai_sync.dart';

import 'support/fake_zonai.dart';

const notes = SyncTable('notes');

/// One device: its own local store and engine, talking to [server].
final class Device {
  Device(
    this.server, {
    this.account = 'u1',
    List<SyncTable> tables = const [notes],
    DateTime? clock,
    int pageSize = 200,
    bool syncOnWrite = false,
  }) {
    now = clock ?? DateTime.utc(2026, 9, 29, 12);
    engine = SyncEngine(
      remote: server,
      local: store,
      tables: tables,
      account: () => account,
      now: () => now,
      pageSize: pageSize,
      syncOnWrite: syncOnWrite,
    );
  }

  final FakeZonai server;
  final store = MemorySyncStore();
  late final SyncEngine engine;
  late DateTime now;
  String? account;

  Map<String, Object?>? row(String id, [String table = 'notes']) =>
      store.rows(table)[id]?.data;

  Future<void> write(Map<String, Object?> row, [String table = 'notes']) =>
      engine.write(table, {'owner_id': account, ...row});
}

void main() {
  late FakeZonai server;
  setUp(() => server = FakeZonai());

  group('gravity_brew bug classes cannot recur', () {
    test('#1 rows never updated after creation reach other devices', () async {
      // The server stamps updated_at on INSERT, and the first pull starts
      // from "nothing", not from a timestamp that NULL never exceeds.
      server
        ..serverWrite('notes', {
          'id': 'a',
          'owner_id': 'u1',
          'body': 'created once',
        })
        ..serverWrite('notes', {
          'id': 'b',
          'owner_id': 'u1',
          'body': 'also once',
        });
      final phone = Device(server);
      await phone.engine.sync();
      expect(phone.row('a')?['body'], 'created once');
      expect(phone.row('b')?['body'], 'also once');
    });

    test('#2 a new row is pushed as a create, never update-first', () async {
      // tableLevelUpdateCheck: updating a missing row is a 403 before any
      // lookup, exactly as zonai's table rules answer. An engine that tries
      // update-then-create never reaches the create.
      final phone = Device(server);
      await phone.write({'id': 'n1', 'body': 'hello'});
      await phone.engine.sync();
      expect(server.calls.where((c) => c.startsWith('update')), isEmpty);
      expect(server.calls, contains('create notes/n1'));
      expect(server.tables['notes']!['n1']!['body'], 'hello');
      expect(phone.engine.currentStatus.deadLetters, isEmpty);
    });

    test(
      '#3 every pull of an owned table is scoped to the signed-in user',
      () async {
        // Another user's newer row would 403 an unscoped list as a whole.
        server
          ..serverWrite('notes', {'id': 'mine', 'owner_id': 'u1'})
          ..serverWrite('notes', {'id': 'theirs', 'owner_id': 'u2'});
        final phone = Device(server);
        await phone.engine.sync();
        expect(server.unscopedPulls, 0);
        expect(phone.row('mine'), isNotNull);
        expect(phone.row('theirs'), isNull);
        expect(phone.engine.currentStatus.lastError, isNull);
      },
    );

    test(
      '#4 conflicts are decided by server revision, not device clocks',
      () async {
        final fastClock = Device(server, clock: DateTime.utc(2099));
        await fastClock.write({'id': 'n1', 'title': 'Essay', 'body': 'v1'});
        await fastClock.engine.sync();

        final slowClock = Device(server, clock: DateTime.utc(1999));
        await slowClock.engine.sync();

        // Both edit offline, different fields, the "future" device first.
        await fastClock.write({
          ...fastClock.row('n1')!,
          'title': 'Essay (final)',
        });
        await slowClock.write({...slowClock.row('n1')!, 'body': 'v2'});
        await fastClock.engine.sync();
        await slowClock.engine.sync();
        await fastClock.engine.sync();

        // Field merge keeps both edits; a clock comparison would have let the
        // 2099 device silently erase the 1999 device's body edit (or vice versa).
        for (final d in [fastClock, slowClock]) {
          expect(d.row('n1')?['title'], 'Essay (final)');
          expect(d.row('n1')?['body'], 'v2');
        }
      },
    );

    test("#5 a new account never inherits the old account's data", () async {
      final phone = Device(server);
      server.offline = true;
      await phone.write({'id': 'secret', 'body': "u1's draft"});
      await phone.engine.sync(); // offline: stays queued
      expect(phone.engine.currentStatus.pending, 1);

      // u2 signs in on the same device.
      phone.account = 'u2';
      server
        ..offline = false
        ..user = 'u2';
      await phone.engine.sync();

      expect(
        server.calls.where((c) => c.contains('secret')),
        isEmpty,
        reason: "u1's queued write must not be pushed with u2's session",
      );
      expect(phone.row('secret'), isNull);
      expect(await phone.store.cursor('notes'), isNull);
      expect(await phone.store.account(), 'u2');
    });
  });

  group('outbox', () {
    test(
      'a row created and deleted before any push never reaches the server',
      () async {
        server.offline = true;
        final phone = Device(server);
        await phone.write({'id': 'tmp'});
        await phone.engine.delete('notes', 'tmp');
        server.offline = false;
        await phone.engine.sync();
        expect(server.calls.where((c) => c.contains('tmp')), isEmpty);
        expect(phone.engine.currentStatus.pending, 0);
      },
    );

    test(
      'several edits coalesce into one push of the union of fields',
      () async {
        final phone = Device(server);
        await phone.write({'id': 'n1', 'a': 1, 'b': 1});
        await phone.engine.sync();
        server.offline = true;
        await phone.write({...phone.row('n1')!, 'a': 2});
        await phone.write({...phone.row('n1')!, 'b': 2});
        final pending = await phone.store.entries();
        expect(pending, hasLength(1));
        expect(pending.single.changedFields, {'a', 'b'});
        server.offline = false;
        await phone.engine.sync();
        expect(server.tables['notes']!['n1']!.values, containsAll([2, 2]));
        expect(server.tables['notes']!['n1']!['rev'], 2);
      },
    );

    test('a delete of a synced row tombstones it on the server', () async {
      final phone = Device(server);
      await phone.write({'id': 'n1'});
      await phone.engine.sync();
      await phone.engine.delete('notes', 'n1');
      await phone.engine.sync();
      expect(server.tables['notes']!['n1']!['deleted_at'], isNotNull);
      expect(phone.row('n1'), isNull);

      final tablet = Device(server);
      await tablet.engine.sync();
      expect(tablet.row('n1'), isNull, reason: 'tombstones propagate');
    });

    test(
      'an edit made while its push is in flight is kept, not dropped',
      () async {
        final phone = Device(server);
        await phone.write({'id': 'n1', 'body': 'first'});
        // The edit lands while the create is on the wire.
        server.whileInFlight = (call) async {
          if (call == 'create notes/n1') {
            server.whileInFlight = null;
            await phone.write({...phone.row('n1')!, 'body': 'second'});
          }
        };
        await phone.engine.sync();
        expect(server.tables['notes']!['n1']!['body'], 'first');
        await phone.engine.sync();
        expect(server.tables['notes']!['n1']!['body'], 'second');
        expect(phone.engine.currentStatus.pending, 0);
      },
    );
  });

  group('failures', () {
    test('offline keeps changes queued without spending attempts', () async {
      final phone = Device(server);
      server.offline = true;
      await phone.write({'id': 'n1'});
      await phone.engine.sync();
      expect(phone.engine.currentStatus.phase, SyncPhase.offline);
      expect((await phone.store.entries()).single.attempts, 0);
      server.offline = false;
      await phone.engine.sync();
      expect(phone.engine.currentStatus.phase, SyncPhase.idle);
      expect(server.tables['notes'], contains('n1'));
    });

    test(
      '403 dead-letters the change instead of retrying it forever',
      () async {
        final phone = Device(server);
        server.failures.add(const SyncRemoteException(FailureKind.forbidden));
        await phone.write({'id': 'n1'});
        await phone.engine.sync();
        final status = phone.engine.currentStatus;
        expect(status.deadLetters, hasLength(1));
        expect(status.pending, 0);
        server.calls.clear();
        await phone.engine.sync();
        expect(
          server.calls.where((c) => c.startsWith('create')),
          isEmpty,
          reason: 'a dead letter is not retried automatically',
        );
        expect(phone.engine.currentStatus.deadLetters, hasLength(1));

        await phone.engine.retryDeadLetter(status.deadLetters.single.id);
        await phone.engine.sync();
        expect(server.tables['notes'], contains('n1'));
        expect(phone.engine.currentStatus.deadLetters, isEmpty);
      },
    );

    test('discarding a dead letter restores the server copy', () async {
      final phone = Device(server);
      await phone.write({'id': 'n1', 'body': 'server'});
      await phone.engine.sync();
      server.failures.add(const SyncRemoteException(FailureKind.invalid));
      await phone.write({...phone.row('n1')!, 'body': 'rejected'});
      await phone.engine.sync();
      final dead = phone.engine.currentStatus.deadLetters.single;
      await phone.engine.discardDeadLetter(dead.id);
      expect(phone.row('n1')?['body'], 'server');
      expect(phone.engine.currentStatus.deadLetters, isEmpty);
    });

    test(
      'server errors back off and dead-letter only after max attempts',
      () async {
        final phone = Device(server);
        await phone.write({'id': 'n1'});
        for (var i = 0; i < 8; i++) {
          server.failures.add(const SyncRemoteException(FailureKind.server));
          phone.now = phone.now.add(
            const Duration(hours: 1),
          ); // past any backoff
          await phone.engine.sync();
        }
        expect(phone.engine.currentStatus.deadLetters, hasLength(1));
      },
    );

    test('backoff: a failed entry is not retried before its delay', () async {
      final phone = Device(server);
      await phone.write({'id': 'n1'});
      server.failures.add(const SyncRemoteException(FailureKind.server));
      await phone.engine.sync();
      final creates = server.calls.where((c) => c.startsWith('create')).length;
      await phone.engine.sync();
      expect(server.calls.where((c) => c.startsWith('create')).length, creates);
      phone.now = phone.now.add(const Duration(minutes: 1));
      await phone.engine.sync();
      expect(server.tables['notes'], contains('n1'));
    });

    test('401 pauses sync until resume', () async {
      final phone = Device(server);
      await phone.write({'id': 'n1'});
      server.user = null;
      await phone.engine.sync();
      expect(phone.engine.currentStatus.phase, SyncPhase.needsAuth);
      server.user = 'u1';
      await phone.engine.sync();
      expect(server.tables['notes'], isNull, reason: 'paused until resume()');
      await phone.engine.resume();
      expect(server.tables['notes'], contains('n1'));
    });

    test('rate limiting defers without spending an attempt', () async {
      final phone = Device(server);
      await phone.write({'id': 'n1'});
      server.failures.add(
        const SyncRemoteException(
          FailureKind.rateLimited,
          retryAfter: Duration(seconds: 30),
        ),
      );
      await phone.engine.sync();
      final entry = (await phone.store.entries()).single;
      expect(entry.attempts, 0);
      expect(
        entry.notBefore,
        phone.now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
      );
    });
  });

  group('pull', () {
    test(
      'pages through every row, including rows sharing a timestamp',
      () async {
        for (var i = 0; i < 450; i++) {
          server.serverWrite('notes', {
            'id': 'r${i.toString().padLeft(3, '0')}',
            'owner_id': 'u1',
          });
          if (i.isEven) server.clock--; // pairs of rows share updated_at
        }
        final phone = Device(server, pageSize: 25);
        await phone.engine.sync();
        expect(phone.store.rows('notes'), hasLength(450));
      },
    );

    test(
      'a pull never overwrites a local change that is still queued',
      () async {
        final phone = Device(server);
        await phone.write({'id': 'n1', 'body': 'v1'});
        await phone.engine.sync();
        server.offline = true;
        await phone.write({...phone.row('n1')!, 'body': 'local edit'});
        server
          ..offline = false
          ..serverWrite('notes', {'id': 'n1', 'title': 'server title'});
        // Push fails once so the pull runs with the edit still queued.
        server.failures.add(const SyncRemoteException(FailureKind.server));
        await phone.engine.sync();
        expect(phone.row('n1')?['body'], 'local edit');
        phone.now = phone.now.add(const Duration(minutes: 5));
        await phone.engine.sync();
        expect(server.tables['notes']!['n1']!['body'], 'local edit');
        expect(server.tables['notes']!['n1']!['title'], 'server title');
      },
    );

    test(
      'incremental pulls fetch only what changed since the cursor',
      () async {
        final phone = Device(server);
        server.serverWrite('notes', {'id': 'a', 'owner_id': 'u1'});
        await phone.engine.sync();
        server.serverWrite('notes', {'id': 'b', 'owner_id': 'u1'});
        await phone.engine.sync();
        expect(phone.store.rows('notes').keys, containsAll(['a', 'b']));
        expect((await phone.store.cursor('notes'))?.id, 'b');
      },
    );
  });

  group('conflict policies', () {
    Future<(Device, Device)> twoDevicesEditing(SyncTable table) async {
      final a = Device(server, tables: [table]);
      await a.write({'id': 'n1', 'x': 0, 'y': 0});
      await a.engine.sync();
      final b = Device(server, tables: [table]);
      await b.engine.sync();
      await a.write({...a.row('n1')!, 'x': 1});
      await b.write({...b.row('n1')!, 'x': 2, 'y': 2});
      await a.engine.sync();
      await b.engine.sync(); // b conflicts with a's newer revision
      await a.engine.sync();
      return (a, b);
    }

    test('serverWins keeps the first-written revision', () async {
      final (a, b) = await twoDevicesEditing(
        const SyncTable('notes', conflict: ConflictPolicy.serverWins),
      );
      expect(server.tables['notes']!['n1']!['x'], 1);
      expect(server.tables['notes']!['n1']!['y'], 0);
      expect(b.row('n1')?['x'], 1, reason: 'the loser adopts the server row');
      expect(a.row('n1')?['x'], 1);
    });

    test('clientWins re-applies the whole local row', () async {
      await twoDevicesEditing(
        const SyncTable('notes', conflict: ConflictPolicy.clientWins),
      );
      expect(server.tables['notes']!['n1']!['x'], 2);
      expect(server.tables['notes']!['n1']!['y'], 2);
    });

    test('customMerge gets both sides and decides', () async {
      await twoDevicesEditing(
        SyncTable(
          'notes',
          conflict: CustomMerge(
            ({required local, required server, required changedFields}) => {
              'x': (local['x']! as int) + (server.data['x']! as int),
            },
          ),
        ),
      );
      expect(server.tables['notes']!['n1']!['x'], 3);
    });

    test(
      'an edit to a row deleted elsewhere resurrects it (field merge)',
      () async {
        final a = Device(server);
        await a.write({'id': 'n1', 'body': 'v1'});
        await a.engine.sync();
        final b = Device(server);
        await b.engine.sync();
        await a.engine.delete('notes', 'n1');
        await a.engine.sync();
        await b.write({...b.row('n1')!, 'body': 'still needed'});
        await b.engine.sync();
        expect(server.tables['notes']!['n1']!['deleted_at'], isNull);
        expect(server.tables['notes']!['n1']!['body'], 'still needed');
      },
    );

    test(
      'two devices creating the same deterministic id merge, not fail',
      () async {
        final a = Device(server);
        final b = Device(server);
        await a.write({'id': 'essay_ada', 'score': 90});
        await b.write({'id': 'essay_ada', 'comment': 'nice'});
        await a.engine.sync();
        await b.engine.sync();
        final row = server.tables['notes']!['essay_ada']!;
        expect(row['score'], 90);
        expect(row['comment'], 'nice');
        expect(b.engine.currentStatus.deadLetters, isEmpty);
      },
    );
  });

  group('review findings (zonai-owner, 2026-09-29)', () {
    test(
      '#1 a delete made while its create is in flight is not lost',
      () async {
        final phone = Device(server);
        await phone.write({'id': 'n1'});
        server.whileInFlight = (call) async {
          if (call == 'create notes/n1') {
            server.whileInFlight = null;
            await phone.engine.delete('notes', 'n1');
          }
        };
        await phone.engine.sync();
        await phone.engine.sync();
        expect(phone.row('n1'), isNull, reason: 'the row must not come back');
        expect(
          server.tables['notes']!['n1']!['deleted_at'],
          isNotNull,
          reason: 'the create landed, so the delete must reach the server',
        );
        expect(phone.engine.currentStatus.pending, 0);
      },
    );

    test(
      '#1b a write made while its delete is in flight revives the row',
      () async {
        final phone = Device(server);
        await phone.write({'id': 'n1', 'body': 'v1'});
        await phone.engine.sync();
        await phone.engine.delete('notes', 'n1');
        server.whileInFlight = (call) async {
          if (call.startsWith('update notes/n1')) {
            server.whileInFlight = null;
            // An app writes its own fields; it doesn't know about deleted_at.
            await phone.write({'id': 'n1', 'body': 'back'});
          }
        };
        await phone.engine.sync();
        await phone.engine.sync();
        final row = server.tables['notes']!['n1']!;
        expect(row['deleted_at'], isNull, reason: 'the later write must win');
        expect(row['body'], 'back');
      },
    );

    test('#2 signing out mid-pull lets nothing back in', () async {
      server.serverWrite('notes', {'id': 'n1', 'owner_id': 'u1'});
      final phone = Device(server);
      server.whileInFlight = (call) async {
        if (call == 'pull notes') {
          server.whileInFlight = null;
          await phone.engine.signOut();
          phone.account = null;
        }
      };
      await phone.engine.sync();
      expect(phone.store.rows('notes'), isEmpty);
      expect(await phone.store.account(), isNull);
      expect(await phone.store.cursor('notes'), isNull);
    });

    test(
      "#2b another account signing in mid-pull never receives the first account's rows",
      () async {
        server.serverWrite('notes', {'id': 'mine', 'owner_id': 'u1'});
        final phone = Device(server);
        server.whileInFlight = (call) async {
          if (call == 'pull notes') {
            server.whileInFlight = null;
            phone.account = 'u2';
            await phone.write({'id': 'theirs'}); // adopts u2's account
          }
        };
        await phone.engine.sync();
        expect(await phone.store.account(), 'u2');
        expect(phone.row('mine'), isNull);
        expect(phone.row('theirs'), isNotNull);
        expect(
          await phone.store.cursor('notes'),
          isNull,
          reason: "u1's cursor would make u2 skip rows",
        );
      },
    );

    test('#3 a child waits while its parent is backing off', () async {
      const courses = SyncTable('courses');
      const students = SyncTable('students', parents: ['courses']);
      final phone = Device(server, tables: const [courses, students]);
      await phone.write({'id': 'c1'}, 'courses');
      server.failures.add(const SyncRemoteException(FailureKind.server));
      await phone.engine.sync(); // parent fails, backs off
      await phone.write({'id': 's1', 'course': 'c1'}, 'students');
      await phone.engine.sync(); // parent not due yet
      expect(server.calls.where((c) => c == 'create students/s1'), isEmpty);
      phone.now = phone.now.add(const Duration(hours: 1));
      await phone.engine.sync();
      expect(server.calls.where((c) => c.startsWith('create')).toList(), [
        'create courses/c1',
        'create students/s1',
      ]);
    });

    test(
      '#4 an unexpected error ends the pass cleanly and never hangs callers',
      () async {
        final phone = Device(server);
        await phone.write({'id': 'n1'});
        server.failures.add(StateError('bug-shaped failure'));
        await phone.engine.sync().timeout(const Duration(seconds: 2));
        expect(phone.engine.currentStatus.lastError, contains('bug-shaped'));
        await phone.engine.sync().timeout(const Duration(seconds: 2));
        expect(
          server.tables['notes'],
          contains('n1'),
          reason: 'next pass recovers',
        );
      },
    );

    test('#5 discarding a dead letter keeps an edit made meanwhile', () async {
      final phone = Device(server);
      await phone.write({'id': 'n1', 'body': 'v1'});
      await phone.engine.sync();
      server.failures.add(const SyncRemoteException(FailureKind.invalid));
      await phone.write({...phone.row('n1')!, 'body': 'rejected'});
      await phone.engine.sync();
      final dead = phone.engine.currentStatus.deadLetters.single;
      server.whileInFlight = (call) async {
        if (call == 'read notes/n1') {
          server.whileInFlight = null;
          await phone.write({...phone.row('n1')!, 'body': 'newer'});
        }
      };
      await phone.engine.discardDeadLetter(dead.id);
      expect(phone.row('n1')?['body'], 'newer');
      expect((await phone.store.entries()).single.state, OutboxState.pending);
    });

    test(
      'pulls re-read an overlap window, so a late-committed row is not skipped',
      () async {
        final phone = Device(server);
        server.serverWrite('notes', {'id': 'a', 'owner_id': 'u1'});
        await phone.engine.sync();
        // A row whose stamp is OLDER than the cursor commits afterwards (several
        // HTTP isolates, or the server clock stepping back).
        server.clock -= 5;
        server.serverWrite('notes', {'id': 'late', 'owner_id': 'u1'});
        server.clock += 10;
        await phone.engine.sync();
        expect(phone.row('late'), isNotNull);
      },
    );
  });

  group('first sign-in', () {
    test(
      'data made before any account is claimed by the first account, not erased',
      () async {
        final phone = Device(server, account: null);
        // Used offline with no account: rows written straight to the store.
        await phone.store.writeRow('notes', {'id': 'draft1', 'body': 'one'});
        await phone.store.writeRow('notes', {'id': 'draft2', 'body': 'two'});

        phone.account = 'u1';
        await phone.engine.sync();

        expect(phone.row('draft1'), isNotNull, reason: 'nothing is erased');
        expect(server.tables['notes']!.keys, containsAll(['draft1', 'draft2']));
        expect(await phone.store.account(), 'u1');
      },
    );

    test('a store owned by one account is still cleared for another', () async {
      final phone = Device(server);
      await phone.write({'id': 'u1-note'});
      await phone.engine.sync();
      phone.account = 'u2';
      server.user = 'u2';
      await phone.engine.sync();
      expect(phone.row('u1-note'), isNull);
    });
  });

  group('ordering and scheduling', () {
    const courses = SyncTable('courses');
    const students = SyncTable('students', parents: ['courses']);

    test(
      'parents are pushed before children regardless of write order',
      () async {
        final phone = Device(server, tables: [students, courses]);
        await phone.write({'id': 's1', 'course': 'c1'}, 'students');
        await phone.write({'id': 'c1'}, 'courses');
        await phone.engine.sync();
        final creates = server.calls
            .where((c) => c.startsWith('create'))
            .toList();
        expect(creates, ['create courses/c1', 'create students/s1']);
      },
    );

    test('a failing parent holds back its children for the pass', () async {
      final phone = Device(server, tables: [courses, students]);
      await phone.write({'id': 'c1'}, 'courses');
      await phone.write({'id': 's1', 'course': 'c1'}, 'students');
      server.failures.add(const SyncRemoteException(FailureKind.server));
      await phone.engine.sync();
      expect(
        server.calls.where((c) => c.startsWith('create students')),
        isEmpty,
        reason: 'the child waits for its parent',
      );
    });

    test('a cycle or unknown parent is rejected up front', () {
      expect(
        () => orderTables(const [
          SyncTable('a', parents: ['b']),
          SyncTable('b', parents: ['a']),
        ]),
        throwsStateError,
      );
      expect(
        () => orderTables(const [
          SyncTable('a', parents: ['nope']),
        ]),
        throwsStateError,
      );
    });

    test('a sync requested while one runs is not dropped', () async {
      final phone = Device(server);
      await phone.write({'id': 'n1'});
      final first = phone.engine.sync();
      // Queued and requested while the first pass is still in flight: the
      // request must schedule another pass, not be swallowed by the running one.
      await phone.write({'id': 'n2'});
      final second = phone.engine.requestSync(force: true);
      await first;
      await second;
      expect(server.tables['notes']!.keys, containsAll(['n1', 'n2']));
    });

    test('a write syncs on its own when syncOnWrite is on', () async {
      final phone = Device(server, syncOnWrite: true);
      await phone.write({'id': 'n1'});
      await phone.engine.requestSync(); // waits for the triggered pass
      expect(server.tables['notes'], contains('n1'));
    });

    test('pull-only tables refuse local writes', () {
      final phone = Device(
        server,
        tables: const [SyncTable('notes', mode: SyncMode.pullOnly)],
      );
      expect(() => phone.write({'id': 'x'}), throwsStateError);
    });

    test('sign out erases everything and stops syncing', () async {
      final phone = Device(server);
      await phone.write({'id': 'n1'});
      await phone.engine.sync();
      await phone.engine.signOut();
      phone.account = null;
      expect(phone.store.rows('notes'), isEmpty);
      expect(await phone.store.entries(), isEmpty);
      await phone.engine.sync();
      expect(phone.engine.currentStatus.phase, SyncPhase.signedOut);
    });
  });
}
