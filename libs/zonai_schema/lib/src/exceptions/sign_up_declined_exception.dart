/// Thrown from [AuthExtension.beforeSignUp] to refuse a sign-up.
///
/// The hook runs before the auth row is inserted, so throwing this leaves no
/// row, no session and no verification email behind — the caller is answered
/// **403** carrying [reason], and nothing was created to undo.
///
/// ## Why this class carries its own parser
///
/// Extensions run in a worker process. The only thing that crosses that
/// boundary on failure is `MessageErrorResponse`, whose fields are `String`s
/// — the host receives `error.toString()` and nothing else, so an exception
/// arrives having lost its type. Every other typed failure in this codebase
/// is recovered by matching on the message text host-side
/// (`exception_mapper.dart:tryParseSchemaException` is the same idiom).
///
/// The difference here is that the encoder and the decoder are the *same
/// file*: [toString] writes [_marker] and [tryParse] reads it. A regex living
/// three packages away from the `toString` it depends on is a coupling
/// nothing checks; keeping the pair adjacent makes it one edit instead of
/// two, and `sign_up_declined_exception_test.dart` round-trips it.
///
/// In-process extensions (`HostWorkerRegistries.useInProcessExtensions`, the
/// shape unit tests use) never serialize at all and arrive as the real
/// object. Both paths are handled where the hook is dispatched.
final class SignUpDeclinedException implements Exception {
  const SignUpDeclinedException([this.reason = _defaultReason]);

  /// Recovers a [SignUpDeclinedException] from the text an extension worker
  /// sent back, or `null` when [message] describes some other failure.
  ///
  /// Deliberately not anchored to the start: the worker wraps the cause in
  /// its own framing (`Error handling request: <cause>`), so the marker sits
  /// mid-string. Everything after it is the reason, newlines included.
  static SignUpDeclinedException? tryParse(String message) {
    final at = message.indexOf(_marker);
    if (at < 0) return null;

    final reason = message.substring(at + _marker.length).trim();
    return SignUpDeclinedException(reason.isEmpty ? _defaultReason : reason);
  }

  /// What the caller is told. Chosen by the app, and rendered in the 403 body
  /// verbatim — so it must not carry anything the caller should not see.
  final String reason;

  static const _defaultReason = 'Sign-up declined';

  /// The needle [tryParse] looks for. Changing it is a protocol change: a
  /// server running the new text and a worker compiled against the old one
  /// would fail the sign-up with a 500 instead of a 403.
  static const _marker = 'zonai:sign-up-declined: ';

  @override
  String toString() => '$_marker$reason';
}
