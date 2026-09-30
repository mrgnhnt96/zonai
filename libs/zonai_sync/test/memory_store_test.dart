import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai_sync/zonai_sync.dart';

void main() {
  test('concurrent transactions are serialized, not nested', () async {
    // Review finding #8: a depth counter shared by everything made a
    // concurrent write run "inside" another transaction and roll back with it.
    final store = MemorySyncStore();
    final firstStarted = Completer<void>();
    final release = Completer<void>();

    final failing = store.transaction(() async {
      await store.writeRow('notes', {'id': 'doomed'});
      firstStarted.complete();
      await release.future;
      throw StateError('first transaction fails');
    });
    await firstStarted.future;

    final independent = store.transaction(
      () => store.writeRow('notes', {'id': 'kept'}),
    );
    release.complete();
    await expectLater(failing, throwsStateError);
    await independent;

    expect(store.rows('notes').keys, ['kept']);
  });

  test('a transaction opened inside another joins it', () async {
    final store = MemorySyncStore();
    await expectLater(
      store.transaction(() async {
        await store.transaction(() => store.writeRow('notes', {'id': 'inner'}));
        throw StateError('outer fails');
      }),
      throwsStateError,
    );
    expect(store.rows('notes'), isEmpty, reason: 'inner work rolls back too');
  });
}
