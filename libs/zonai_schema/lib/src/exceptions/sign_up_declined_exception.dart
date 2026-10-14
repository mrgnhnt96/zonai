/// Thrown from [AuthExtension.beforeSignUp] to refuse a sign-up.
///
/// The hook runs before the auth row is inserted, so throwing this leaves no
/// row, no session and no verification email behind — the caller is answered
/// **403** carrying [reason], and nothing was created to undo.
///
/// From an extensions worker it travels as `MessageErrorResponse.refusal`, a
/// structured field (see `worker_refusal.dart`), and the host rebuilds it in
/// `_runExtension`. In-process extensions
/// (`HostWorkerRegistries.useInProcessExtensions`) never serialize, and it
/// arrives as the real object.
final class SignUpDeclinedException implements Exception {
  const SignUpDeclinedException([this.reason = _defaultReason]);

  /// What the caller is told. Chosen by the app, and rendered in the 403 body
  /// verbatim — so it must not carry anything the caller should not see.
  final String reason;

  static const _defaultReason = 'Sign-up declined';

  @override
  String toString() => 'SignUpDeclinedException: $reason';
}
