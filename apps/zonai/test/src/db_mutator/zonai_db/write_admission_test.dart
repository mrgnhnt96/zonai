import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/write_admission.dart';

class _Refused implements Exception {
  const _Refused();
}

/// Every test runs under [FakeAsync] so the wait window is elapsed by hand;
/// nothing here sleeps for real.
void main() {
  const window = Duration(milliseconds: 250);

  WriteAdmission gate({int slots = 2, int waiters = 2}) => WriteAdmission(
    maxAdmitted: slots,
    maxWaiters: waiters,
    waitWindow: window,
    onRefused: () => const _Refused(),
  );

  /// Admits synchronously-as-far-as-possible and records the outcome, so a
  /// test can inspect it after elapsing fake time.
  ({Future<WriteSlot> future, List<Object> outcome}) attempt(
    WriteAdmission admission,
  ) {
    final outcome = <Object>[];
    final future = admission.admit();
    future.then(outcome.add, onError: (Object e) => outcome.add(e));
    return (future: future, outcome: outcome);
  }

  group('WriteAdmission', () {
    test('admits immediately while a slot is free', () {
      fakeAsync((async) {
        final admission = gate(slots: 2);
        final a = attempt(admission);
        final b = attempt(admission);
        async.flushMicrotasks();

        expect(a.outcome.single, isA<WriteSlot>());
        expect(b.outcome.single, isA<WriteSlot>());
        expect(admission.admitted, 2);
        expect(admission.waiting, 0);
      });
    });

    test('a full queue refuses once the window expires', () {
      fakeAsync((async) {
        final admission = gate(slots: 1, waiters: 4);
        final held = attempt(admission);
        final waiter = attempt(admission);
        async.flushMicrotasks();

        expect(held.outcome.single, isA<WriteSlot>());
        expect(waiter.outcome, isEmpty, reason: 'still inside the window');
        expect(admission.waiting, 1);

        async.elapse(window - const Duration(milliseconds: 1));
        expect(waiter.outcome, isEmpty, reason: 'one ms short of the window');

        async.elapse(const Duration(milliseconds: 1));
        expect(waiter.outcome.single, isA<_Refused>());
        expect(admission.waiting, 0, reason: 'a timed-out waiter is dropped');
        expect(admission.admitted, 1, reason: 'the held slot is untouched');
      });
    });

    test('a waiter is admitted when a slot frees inside the window', () {
      fakeAsync((async) {
        final admission = gate(slots: 1, waiters: 4);
        final held = attempt(admission);
        final waiter = attempt(admission);
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 100));
        (held.outcome.single as WriteSlot).release();
        async.flushMicrotasks();

        expect(waiter.outcome.single, isA<WriteSlot>());
        expect(admission.admitted, 1, reason: 'the slot changed hands');
        expect(admission.waiting, 0);

        // The waiter's expiry timer was cancelled on hand-off: elapsing past
        // the window must not refuse a slot that was already granted.
        async.elapse(window * 2);
        expect(waiter.outcome, hasLength(1));
      });
    });

    test('waiters are admitted in FIFO order', () {
      fakeAsync((async) {
        final admission = gate(slots: 1, waiters: 8);
        final held = attempt(admission);
        final order = <int>[];
        final waiters = List.generate(5, (i) {
          final w = attempt(admission);
          w.future.then((_) => order.add(i), onError: (_) {});
          return w;
        });
        async.flushMicrotasks();
        expect(admission.waiting, 5);

        // Release the held slot, then each waiter's slot as it is granted,
        // so the slot walks down the queue one hand-off at a time.
        (held.outcome.single as WriteSlot).release();
        async.flushMicrotasks();
        for (final w in waiters) {
          (w.outcome.single as WriteSlot).release();
          async.flushMicrotasks();
        }

        expect(order, [0, 1, 2, 3, 4]);
        expect(admission.admitted, 0);
      });
    });

    test('a newcomer cannot jump the queue while anyone is waiting', () {
      fakeAsync((async) {
        final admission = gate(slots: 1, waiters: 8);
        final held = attempt(admission);
        final first = attempt(admission);
        async.flushMicrotasks();

        // The slot is handed straight to `first`; `admitted` never dips, so
        // a caller arriving in the same tick sees a full house and queues.
        (held.outcome.single as WriteSlot).release();
        final late = attempt(admission);
        async.flushMicrotasks();

        expect(first.outcome.single, isA<WriteSlot>());
        expect(late.outcome, isEmpty);
        expect(admission.waiting, 1);
      });
    });

    test('past the waiter bound, refusal is immediate', () {
      fakeAsync((async) {
        final admission = gate(slots: 1, waiters: 2);
        attempt(admission);
        attempt(admission);
        attempt(admission);
        final overflow = attempt(admission);
        async.flushMicrotasks();

        expect(admission.admitted, 1);
        expect(admission.waiting, 2);
        expect(
          overflow.outcome.single,
          isA<_Refused>(),
          reason: 'no timer ran: refused without waiting',
        );
      });
    });

    test('refusals carry an empty stack trace, on both paths', () {
      fakeAsync((async) {
        final admission = gate(slots: 1, waiters: 1);
        attempt(admission);
        final timedOut = admission.admit();
        final immediate = admission.admit();

        final stacks = <String, String>{};
        timedOut.then(
          (_) {},
          onError: (Object e, StackTrace s) {
            stacks['timedOut'] = '$s';
          },
        );
        immediate.then(
          (_) {},
          onError: (Object e, StackTrace s) {
            stacks['immediate'] = '$s';
          },
        );
        async.elapse(window);

        expect(stacks, {'timedOut': '', 'immediate': ''});
      });
    });

    test('releasing a slot twice does not create a second slot', () {
      fakeAsync((async) {
        final admission = gate(slots: 1, waiters: 4);
        final held = attempt(admission);
        async.flushMicrotasks();
        final slot = held.outcome.single as WriteSlot;

        slot.release();
        slot.release();
        expect(admission.admitted, 0);

        // Were the double release counted, `admitted` would be -1 here and
        // two callers would fit through a one-slot gate.
        attempt(admission);
        final second = attempt(admission);
        async.flushMicrotasks();
        expect(admission.admitted, 1);
        expect(second.outcome, isEmpty, reason: 'second caller must wait');
      });
    });

    test('a waiter that times out does not disturb the ones behind it', () {
      fakeAsync((async) {
        final admission = gate(slots: 1, waiters: 4);
        final held = attempt(admission);
        final early = attempt(admission);
        async.elapse(const Duration(milliseconds: 200));
        final late = attempt(admission);
        async.flushMicrotasks();
        expect(admission.waiting, 2);

        // `early` expires at 250ms; `late` still has 200ms to go.
        async.elapse(const Duration(milliseconds: 50));
        expect(early.outcome.single, isA<_Refused>());
        expect(late.outcome, isEmpty);
        expect(admission.waiting, 1);

        (held.outcome.single as WriteSlot).release();
        async.flushMicrotasks();
        expect(late.outcome.single, isA<WriteSlot>());
      });
    });
  });
}
