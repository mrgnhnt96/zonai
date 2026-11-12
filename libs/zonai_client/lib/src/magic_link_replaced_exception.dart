import 'package:revali_client/revali_client.dart' show ServerException;

/// The magic link was valid, but a newer one has been sent to the same
/// address since, and that one replaced it.
///
/// Thrown by [ZonaiClient.auth.confirm] for a `verifyMagicLink` body. Nobody
/// was signed in, and the newer link still works. The recovery is "open the
/// newest email", not "request another link", which is why this is a type to
/// catch rather than a message.
///
/// Translated from the raw [ServerException]: the server answers `401` with
/// the `magic_link_replaced` envelope, and [tryFrom] is the whole translation.
class MagicLinkReplacedException implements Exception {
  const MagicLinkReplacedException({required this.message});

  /// Builds one from [exception] when it carries this error, and `null`
  /// otherwise -- any other failure keeps its own type.
  static MagicLinkReplacedException? tryFrom(ServerException exception) {
    if (exception.code != code) return null;
    return MagicLinkReplacedException(
      message: exception.reason ?? exception.message,
    );
  }

  /// The server's stable identifier for this failure -- the thing to branch on.
  static const code = 'magic_link_replaced';

  /// The server's human-readable explanation. Never parse it; branch on the
  /// type.
  final String message;

  @override
  String toString() => 'MagicLinkReplacedException: $message';
}
