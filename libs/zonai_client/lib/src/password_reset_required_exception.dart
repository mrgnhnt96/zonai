import 'package:revali_client/revali_client.dart' show ServerException;

/// The server refused a password sign-in because the account owes a new
/// password, and handed back a one-time ticket instead of a session.
///
/// A caller that treats every non-2xx from sign-in as "bad credentials" gets
/// this wrong twice: the credentials were *correct*, and the response carries
/// the one thing needed to recover. See `docs/auth.md`, "Forced password
/// reset". Complete it with [ZonaiClient.auth.completePasswordReset].
///
/// This is translated from the raw [ServerException] rather than being a
/// distinct transport failure — `revali_client` throws `ServerException` for
/// every non-2xx, and `ServerException.fromBody` already parses zonai's
/// structured envelope. [tryFrom] is the whole translation.
class PasswordResetRequiredException implements Exception {
  const PasswordResetRequiredException({
    required this.resetToken,
    required this.expiresIn,
    required this.reason,
    required this.message,
  });

  /// Builds one from [exception] when it carries this error, and `null`
  /// otherwise.
  ///
  /// Everything is checked before anything is built: a 403 whose `code` is
  /// something else, or one with no `resetToken`, is somebody else's failure
  /// and must keep its own type rather than being reshaped into this one.
  static PasswordResetRequiredException? tryFrom(ServerException exception) {
    if (exception.code != code) return null;

    final details = exception.details;
    final token = details?['resetToken'];
    if (token is! String || token.isEmpty) return null;

    // Seconds on the wire. A `Duration` renders as milliseconds by default, so
    // reading this as one without the conversion would tell a caller the ticket
    // is good for 15 000 minutes.
    final seconds = details?['expiresIn'];
    final expiresIn = Duration(seconds: seconds is int ? seconds : 0);

    final reason = details?['reason'];

    return PasswordResetRequiredException(
      resetToken: token,
      expiresIn: expiresIn,
      reason: reason is String ? reason : '',
      message: exception.reason ?? exception.message,
    );
  }

  /// The server's stable identifier for this failure — the thing to branch on.
  static const code = 'password_reset_required';

  /// The one-time ticket, to be handed straight back to `POST /auth/confirm`.
  ///
  /// Short-lived (15 minutes at the time of writing, but read [expiresIn]
  /// rather than assuming) because its holder is at the keyboard right now.
  final String resetToken;

  /// How long [resetToken] stays good.
  final Duration expiresIn;

  /// Why the account owes a password, so a client can say something truer than
  /// "you must reset" — `adminForced`, `temporaryPassword`, `compromised` or
  /// `passwordPolicy` today.
  ///
  /// A `String` and not an enum ON PURPOSE. The server's `PasswordResetReason`
  /// lives on an internal table and is not part of `zonai_schema`'s public
  /// surface, and a mirrored enum here would throw on a value a NEWER server
  /// added — turning a recoverable sign-in into a crash for the one client
  /// that has not been updated yet. Empty when the server sent none.
  final String reason;

  /// The server's human-readable explanation. Never parse it; branch on
  /// [code].
  final String message;

  /// Deliberately carries no [resetToken].
  ///
  /// Client exceptions land in crash reporters, analytics breadcrumbs and
  /// `print`. A live credential that reaches any of those outlives the 15
  /// minutes it was supposed to be good for, in a place nobody is watching.
  /// The server-side exception holds the same invariant for the same reason.
  @override
  String toString() =>
      'PasswordResetRequiredException: a new password is required before '
      'signing in${reason.isEmpty ? '' : ' ($reason)'}';
}
