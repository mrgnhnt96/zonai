import 'package:zonai_schema/zonai_schema.dart';

/// The push transport, as the fan-out sees it.
///
/// An interface, unlike email's `Courier`, and the departure is deliberate.
/// Because email's transport is not injectable, `test/src/email/courier_test.dart`
/// can only assert the missing-config warning — there is no test of a
/// successful send, a rejection, or a retry anywhere in the suite. Push must
/// not inherit that gap, and the assertion the whole checkpointing design
/// exists for (crash-resume) is untestable against a real endpoint.
///
/// It also leaves room for a `.p8` APNs implementation later without touching
/// a call site.
abstract interface class PushCourier {
  /// Sends [message] to each of [tokens], returning one outcome per token.
  ///
  /// Implementations must return an outcome for **every** token they were
  /// given, in any order: the fan-out reconciles outcomes against the batch it
  /// read, and a token that simply vanishes would be counted as neither sent
  /// nor failed — a recipient silently dropped at every retry.
  ///
  /// Throwing is reserved for faults that are not about any one token — bad
  /// credentials, an unreachable auth endpoint. The fan-out treats a throw as
  /// a job-level failure and leaves the cursor untouched, because retrying
  /// per-token against broken credentials only burns quota, and pruning on one
  /// would delete every token in the batch.
  Future<List<PushOutcome>> send(
    PushMessage message,
    List<String> tokens, {
    required PushConfig config,
  });

  /// Releases any transport-level resources (HTTP client, cached token).
  Future<void> close();
}

/// Raised when the transport cannot work at all — as distinct from a token
/// the transport rejected.
class PushTransportException implements Exception {
  PushTransportException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message: $cause';
}
