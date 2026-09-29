import 'package:revali_client/revali_client.dart' show ServerException;

/// Upgrading an anonymous account named an address that another account in
/// the same table already holds.
///
/// Raised by [ZonaiClient.auth.confirmUpgrade] only after the code was proven,
/// so it reaches the address's owner and nobody else. The anonymous account is
/// unchanged. The recovery is a different flow -- sign in to the existing
/// account -- which is why this is a type to catch rather than a message.
///
/// Translated from the raw [ServerException]: `revali_client` throws that for
/// every non-2xx, and `ServerException.fromBody` already parses zonai's
/// structured envelope. [tryFrom] is the whole translation.
class EmailInUseException implements Exception {
  const EmailInUseException({required this.message});

  /// Builds one from [exception] when it carries this error, and `null`
  /// otherwise -- a 409 with any other `code` keeps its own type.
  static EmailInUseException? tryFrom(ServerException exception) {
    if (exception.code != code) return null;
    return EmailInUseException(message: exception.reason ?? exception.message);
  }

  /// The server's stable identifier for this failure -- the thing to branch on.
  static const code = 'email_in_use';

  /// The server's human-readable explanation. Never parse it; branch on the
  /// type.
  final String message;

  @override
  String toString() => 'EmailInUseException: $message';
}
