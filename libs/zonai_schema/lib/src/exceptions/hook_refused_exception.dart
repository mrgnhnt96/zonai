import 'package:revali_core/revali_core.dart' show HttpError;

/// A `beforeCreate`, `beforeUpdate` or `beforeDelete` hook's deliberate
/// refusal of the request's own write.
///
/// A hook refuses by throwing an [HttpError] with a 4xx status. `DbExtensions`
/// wraps it in this, around those three hooks only, and the server answers
/// with the [error]'s status and envelope. Any other throw, an [HttpError]
/// outside 4xx or one from an after-hook included, is a server error and
/// stays one.
///
/// From a worker it travels as `MessageErrorResponse.refusal`, a structured
/// field the worker sets only for this and `SignUpDeclinedException`, so
/// nothing is parsed out of error text. See `worker_refusal.dart`.
final class HookRefusedException implements Exception {
  const HookRefusedException(this.error);

  /// Whether [error] is a refusal, rather than a failure: a 4xx.
  static bool refuses(HttpError error) =>
      error.statusCode >= 400 && error.statusCode < 500;

  /// What the caller is answered with. Chosen by the app, and rendered to the
  /// client as is, so it must not carry anything the caller should not see.
  final HttpError error;

  @override
  String toString() => 'HookRefusedException: $error';
}
