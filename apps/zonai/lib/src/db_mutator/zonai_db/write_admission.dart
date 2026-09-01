import 'dart:async';
import 'dart:collection';

/// Admission control for `ZonaiDb`'s single-writer chain, split from the
/// chain itself so a caller can reserve its place *before* the expensive part
/// of a write -- JWT verification, the Argon2 hash -- rather than after.
///
/// Two properties, and each of them was measured missing before this existed
/// (see `stress/README.md`'s create sweep):
///
///  * **Refusal is decided before the work.** `create()` used to verify the
///    bearer token and hash the password inside its scope and only then ask
///    the queue for a slot, so under saturation most requests paid the whole
///    pre-write cost to be told 503. [admit] is the first thing a write does
///    now, and a refused write has cost nothing.
///
///  * **The knee is a curve, not a step.** With a fail-fast queue of 64, a
///    closed-loop client that is refused fires again immediately, and at
///    concurrency 70 the server was spending ~82% of its CPU issuing 503s:
///    2997 successful creates/s at c=64 fell to 545/s at c=70. A caller that
///    finds every slot taken now waits, FIFO, up to [waitWindow] for one to be
///    handed to it; only a caller that arrives when [maxWaiters] are already
///    waiting -- or whose window expires -- is refused.
///
/// The slot is *reserved*, not merely checked: [admit] returns a [WriteSlot]
/// the caller holds through its pre-work and its chained write and releases in
/// a `finally`. A check-then-work-then-enqueue would let a hundred requests
/// pass the check and all of them enqueue.
///
/// Release hands the slot **directly** to the head waiter rather than
/// decrementing and letting the next arrival race for it, which is what makes
/// the order FIFO: [admitted] never dips while anyone is waiting, so a
/// newcomer always sees a full house and queues behind.
final class WriteAdmission {
  WriteAdmission({
    required this.maxAdmitted,
    required this.maxWaiters,
    required this.waitWindow,
    required this.onRefused,
  });

  /// Slots: writes admitted and not yet released, whether still hashing or
  /// already on the chain.
  final int maxAdmitted;

  /// Callers allowed to wait for a slot at once. Past this, refusal is
  /// immediate -- a bounded wait is only a bounded amount of memory if the
  /// number of waiters is bounded too.
  final int maxWaiters;

  /// How long a caller waits for a slot before it is refused.
  final Duration waitWindow;

  /// Builds the exception a refused caller receives.
  final Object Function() onRefused;

  var _admitted = 0;
  final Queue<_Waiter> _waiters = Queue<_Waiter>();

  /// Slots currently held.
  int get admitted => _admitted;

  /// Callers currently waiting for a slot.
  int get waiting => _waiters.length;

  /// Reserves a slot, waiting up to [waitWindow] for one if none is free.
  ///
  /// Throws [onRefused] -- with an empty stack trace, see [_refuse] -- when
  /// [maxWaiters] callers are already waiting, or when the window expires.
  Future<WriteSlot> admit() async {
    if (_waiters.isEmpty && _admitted < maxAdmitted) {
      _admitted++;
      return WriteSlot._(this);
    }
    if (_waiters.length >= maxWaiters) {
      _refuse();
    }

    final waiter = _Waiter();
    _waiters.addLast(waiter);
    final expiry = Timer(waitWindow, () {
      if (waiter.handedOff.isCompleted) return;
      _waiters.remove(waiter);
      // Same empty stack as the immediate refusal, for the same reason.
      waiter.handedOff.completeError(onRefused(), StackTrace.empty);
    });
    try {
      // On hand-off the releasing slot's count transfers to this waiter, so
      // there is nothing to increment here.
      await waiter.handedOff.future;
    } finally {
      expiry.cancel();
    }
    return WriteSlot._(this);
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().handedOff.complete();
      return;
    }
    _admitted--;
  }

  /// Thrown with an EMPTY stack on purpose, and that is a throughput fix
  /// rather than tidiness. The catcher answers backpressure with 503, and
  /// revali's `Router._authoredResponse` logs every response >= 500 through
  /// `print('Request failed: $error\n${Trace.format(stackTrace)}')`. Under
  /// saturation that runs on the *reject* path, so shedding load costs more
  /// than serving it: measured AOT, formatting and printing this 23-frame
  /// trace is 2.13ms per rejection versus 21us with `StackTrace.empty`,
  /// while a whole successful create is 0.35ms. Rejecting 5794 requests in
  /// a 5s window therefore asks for ~12s of single-threaded work, so the
  /// event loop starves the writes it *did* admit and successful
  /// throughput collapses instead of levelling off (2860/s at concurrency
  /// 64 -> 116/s at 70). See stress/README.md for the sweep.
  ///
  /// Nothing diagnostic is lost: the trace is identical on every rejection
  /// and names only this method and its callers, while the message
  /// already says exactly what happened. What it did produce was 40MB of
  /// serve log per 15s of saturated load -- a disk-fill hazard on the one
  /// path that fires when the server is already in trouble.
  Never _refuse() {
    Error.throwWithStackTrace(onRefused(), StackTrace.empty);
  }
}

/// A reserved place on the write chain. [release] exactly once, in a
/// `finally`; a second call is a no-op so a double release cannot hand out a
/// slot that was never held.
final class WriteSlot {
  WriteSlot._(this._admission);

  final WriteAdmission _admission;
  var _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _admission._release();
  }
}

final class _Waiter {
  final Completer<void> handedOff = Completer<void>();
}
