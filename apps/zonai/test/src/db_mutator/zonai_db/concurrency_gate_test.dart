import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/concurrency_gate.dart';

class _Saturated implements Exception {
  const _Saturated();
}

void main() {
  group('ConcurrencyGate', () {
    test('admits calls up to maxConcurrent, then fails fast', () async {
      final gate = ConcurrencyGate(
        maxConcurrent: 3,
        onSaturated: () => const _Saturated(),
      );

      // Three bodies that stay in flight until released, so the 4th and 5th
      // callers are guaranteed to see the gate still full.
      final releases = List.generate(3, (_) => Completer<void>());
      final admitted = List.generate(
        3,
        (i) => gate.run(() => releases[i].future),
      );

      // The gate's check-and-increment runs synchronously before the first
      // await inside `run`, so by the time these two extra calls are made,
      // `pending` already reflects all three admitted calls above.
      expect(gate.pending, 3);
      expect(() => gate.run(() async {}), throwsA(isA<_Saturated>()));
      expect(() => gate.run(() async {}), throwsA(isA<_Saturated>()));

      for (final r in releases) {
        r.complete();
      }
      await Future.wait(admitted);
      expect(gate.pending, 0);

      // Once slots free up, new calls are admitted again.
      await expectLater(gate.run(() async => 'ok'), completion('ok'));
    });

    test('a body that throws still frees its slot', () async {
      final gate = ConcurrencyGate(
        maxConcurrent: 1,
        onSaturated: () => const _Saturated(),
      );

      await expectLater(
        gate.run(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      expect(gate.pending, 0);

      // The slot was freed, so this doesn't hit onSaturated.
      await expectLater(gate.run(() async => 'ok'), completion('ok'));
    });

    test(
      '30 concurrent callers against a cap of 20 admits exactly 20',
      () async {
        final gate = ConcurrencyGate(
          maxConcurrent: 20,
          onSaturated: () => const _Saturated(),
        );
        final hold = Completer<void>();

        // `List.generate` invokes `gate.run(...)` for every element right away
        // -- each call runs synchronously up to its first `await`, so by the
        // time this list is built, all 30 admission checks have already
        // happened, in order, with no interleaving.
        final futures = List.generate(
          30,
          (_) => gate
              .run(() => hold.future)
              .then<Object?>((_) => null)
              .catchError((Object e) => e),
        );

        expect(gate.pending, 20, reason: 'exactly the cap should be admitted');

        hold.complete();
        final results = await Future.wait(futures);

        expect(results.whereType<_Saturated>().length, 10);
        expect(results.where((r) => r == null).length, 20);
      },
    );
  });
}
