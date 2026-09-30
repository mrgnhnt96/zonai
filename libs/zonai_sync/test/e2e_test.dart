@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_sync/zonai_sync.dart';

/// zonai_sync against a REAL zonai server (fixture: e2e/sync).
///
/// Needs a compiled zonai binary whose version matches e2e/sync/zonai.yaml:
///
///     ZONAI_E2E_BINARY=/path/to/zonai dart test --tags e2e
///
/// Skipped (loudly) without it. The in-memory fake in engine_test.dart pins
/// the engine's logic; this pins the ASSUMPTIONS the fake makes about zonai —
/// server-stamped updated_at on insert, whole-list 403 on an invisible row,
/// conditional updates on `rev`, table rules checked before the row lookup.
void main() {
  final binary = Platform.environment['ZONAI_E2E_BINARY'];
  if (binary == null) {
    test(
      'zonai e2e',
      () {},
      skip:
          'set ZONAI_E2E_BINARY to a compiled zonai to run against a real server',
    );
    return;
  }

  final fixture = Directory(
    '${Directory.current.path}/../../e2e/sync',
  ).absolute;
  const port = 8791;
  final baseUrl = Uri.parse('http://localhost:$port');
  late Process server;
  final serverLog = StringBuffer();

  Future<void> zonai(List<String> args) async {
    final r = await Process.run(binary, args, workingDirectory: fixture.path);
    if (r.exitCode != 0) {
      fail('zonai ${args.join(' ')} failed:\n${r.stdout}\n${r.stderr}');
    }
  }

  setUpAll(() async {
    final data = Directory('${fixture.path}/.zonai/data');
    if (data.existsSync()) data.deleteSync(recursive: true);
    await zonai(['compile']);
    if (!Directory('${fixture.path}/.zonai/migrations').existsSync()) {
      await zonai(['db', 'migrate', 'generate', '--name', 'init']);
    }
    await zonai(['db', 'migrate', 'apply']);
    server = await Process.start(binary, [
      'serve',
      '--port',
      '$port',
      '--release',
      '--no-version-check',
      '--no-schema-version-check',
    ], workingDirectory: fixture.path);
    server.stdout
        .transform(const SystemEncoding().decoder)
        .listen(serverLog.write);
    server.stderr
        .transform(const SystemEncoding().decoder)
        .listen(serverLog.write);
    final client = HttpClient();
    for (var i = 0; i < 120; i++) {
      try {
        final res = await (await client.getUrl(
          baseUrl.resolve('/health'),
        )).close();
        if (res.statusCode == 200) break;
      } on SocketException {
        // not up yet
      }
      if (i == 119) fail('server did not come up:\n$serverLog');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    client.close();
  });

  tearDownAll(() async {
    server.kill();
    await server.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () => -1,
    );
  });

  var emails = 0;

  /// A signed-in user: their id and a way to make more of their devices.
  Future<({String id, ZonaiClient Function() device})> user() async {
    final email =
        'teacher${emails++}.${DateTime.now().microsecondsSinceEpoch}@example.com';
    const password = 'correct-horse-battery-staple-9';
    final first = ZonaiClient(baseUrl: baseUrl);
    final session = await first.auth.signUp(
      body: SignUpAuthBody(table: 'users', email: email, password: password),
    );
    final id = session!.user['id']! as String;
    ZonaiClient device() {
      final c = ZonaiClient(baseUrl: baseUrl);
      unawaited(
        c.auth.signIn(
          body: SignInAuthBody(
            table: 'users',
            email: email,
            password: password,
          ),
        ),
      );
      return c;
    }

    return (id: id, device: device);
  }

  test('rows created once and never edited reach another device', () async {
    final u = await user();
    final phoneStore = MemorySyncStore();
    final phone = SyncEngine(
      remote: ZonaiSyncRemote(u.device()),
      local: phoneStore,
      tables: const [SyncTable('notes')],
      account: () => u.id,
      syncOnWrite: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final n in ['a', 'b', 'c']) {
      await phone.write('notes', {
        'id': '${u.id}_$n',
        'owner_id': u.id,
        'title': n,
      });
    }
    await phone.sync();
    expect(
      phone.currentStatus.pending,
      0,
      reason: '${phone.currentStatus}\n$serverLog',
    );

    final tabletStore = MemorySyncStore();
    final tablet = SyncEngine(
      remote: ZonaiSyncRemote(u.device()),
      local: tabletStore,
      tables: const [SyncTable('notes')],
      account: () => u.id,
      syncOnWrite: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tablet.sync();
    expect(
      tabletStore.rows('notes').keys,
      containsAll(['${u.id}_a', '${u.id}_b', '${u.id}_c']),
    );
    expect(tabletStore.rows('notes')['${u.id}_a']!.data['title'], 'a');
  });

  test("another user's rows never break or leak into a pull", () async {
    final teacher = await user();
    final other = await user();
    final theirs = SyncEngine(
      remote: ZonaiSyncRemote(other.device()),
      local: MemorySyncStore(),
      tables: const [SyncTable('notes')],
      account: () => other.id,
      syncOnWrite: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await theirs.write('notes', {
      'id': '${other.id}_x',
      'owner_id': other.id,
      'title': 'private',
    });
    await theirs.sync();

    final store = MemorySyncStore();
    final mine = SyncEngine(
      remote: ZonaiSyncRemote(teacher.device()),
      local: store,
      tables: const [SyncTable('notes')],
      account: () => teacher.id,
      syncOnWrite: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await mine.write('notes', {
      'id': '${teacher.id}_m',
      'owner_id': teacher.id,
    });
    await mine.sync();
    expect(
      mine.currentStatus.lastError,
      isNull,
      reason: 'an unscoped list would 403 here',
    );
    expect(store.rows('notes').keys, ['${teacher.id}_m']);
  });

  test('concurrent offline edits to different fields both survive', () async {
    final u = await user();
    final aStore = MemorySyncStore();
    final bStore = MemorySyncStore();
    final a = SyncEngine(
      remote: ZonaiSyncRemote(u.device()),
      local: aStore,
      tables: const [SyncTable('notes')],
      account: () => u.id,
      syncOnWrite: false,
    );
    final b = SyncEngine(
      remote: ZonaiSyncRemote(u.device()),
      local: bStore,
      tables: const [SyncTable('notes')],
      account: () => u.id,
      syncOnWrite: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final id = '${u.id}_essay';
    await a.write('notes', {
      'id': id,
      'owner_id': u.id,
      'title': 'Essay',
      'body': 'v1',
    });
    await a.sync();
    await b.sync();

    await a.write('notes', {
      ...aStore.rows('notes')[id]!.data,
      'title': 'Essay (final)',
    });
    await b.write('notes', {...bStore.rows('notes')[id]!.data, 'body': 'v2'});
    await a.sync();
    await b.sync(); // conditional update fails on rev -> field merge
    await a.sync();

    for (final store in [aStore, bStore]) {
      expect(store.rows('notes')[id]!.data['title'], 'Essay (final)');
      expect(store.rows('notes')[id]!.data['body'], 'v2');
    }
    expect(
      aStore.rows('notes')[id]!.baseRev,
      2,
      reason: 'created at 0, then one update per device',
    );
  });

  test('deletes propagate as tombstones', () async {
    final u = await user();
    final aStore = MemorySyncStore();
    final bStore = MemorySyncStore();
    final a = SyncEngine(
      remote: ZonaiSyncRemote(u.device()),
      local: aStore,
      tables: const [SyncTable('notes')],
      account: () => u.id,
      syncOnWrite: false,
    );
    final b = SyncEngine(
      remote: ZonaiSyncRemote(u.device()),
      local: bStore,
      tables: const [SyncTable('notes')],
      account: () => u.id,
      syncOnWrite: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final id = '${u.id}_gone';
    await a.write('notes', {'id': id, 'owner_id': u.id});
    await a.sync();
    await b.sync();
    expect(bStore.rows('notes'), contains(id));
    await a.delete('notes', id);
    await a.sync();
    await b.sync();
    expect(bStore.rows('notes'), isNot(contains(id)));
  });

  test('pages through more rows than one page holds', () async {
    final u = await user();
    final aStore = MemorySyncStore();
    final a = SyncEngine(
      remote: ZonaiSyncRemote(u.device()),
      local: aStore,
      tables: const [SyncTable('notes')],
      account: () => u.id,
      syncOnWrite: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (var i = 0; i < 23; i++) {
      await a.write('notes', {
        'id': '${u.id}_p${i.toString().padLeft(2, '0')}',
        'owner_id': u.id,
      });
    }
    await a.sync();
    final bStore = MemorySyncStore();
    final b = SyncEngine(
      remote: ZonaiSyncRemote(u.device()),
      local: bStore,
      tables: const [SyncTable('notes')],
      account: () => u.id,
      pageSize: 5,
      syncOnWrite: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await b.sync();
    expect(bStore.rows('notes'), hasLength(23));
  });

  test(
    "writing a row owned by someone else is dead-lettered, not retried",
    () async {
      final u = await user();
      final other = await user();
      final a = SyncEngine(
        remote: ZonaiSyncRemote(u.device()),
        local: MemorySyncStore(),
        tables: const [SyncTable('notes')],
        account: () => u.id,
        syncOnWrite: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await a.write('notes', {'id': '${u.id}_forged', 'owner_id': other.id});
      await a.sync();
      expect(a.currentStatus.deadLetters, hasLength(1));
      expect(a.currentStatus.pending, 0);
    },
  );
}
