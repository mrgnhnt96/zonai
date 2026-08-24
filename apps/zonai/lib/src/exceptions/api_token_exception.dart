/// Refusals involving API tokens.
///
/// Presenting an *unknown, revoked or expired* token is not one of these: that
/// answers `InvalidJwtException`, flatly, the way every other credential
/// failure does. These are the two cases where the token is real and the
/// answer is still no -- a scope that could not have been meant, and a
/// credential offered somewhere it is never accepted.
sealed class ApiTokenException implements Exception {
  const ApiTokenException();
}

/// The requested scope could not have been honoured, so no row was written.
///
/// Refused at creation rather than at use on purpose: a token whose scope is
/// nonsense is a token someone believes works, and they will find out when
/// their integration is already deployed.
final class InvalidApiTokenScopeException extends ApiTokenException {
  const InvalidApiTokenScopeException(this.reason);

  final String reason;

  @override
  String toString() => 'Invalid API token scope: $reason';
}

/// No `_api_tokens` row has this id.
final class ApiTokenNotFoundException extends ApiTokenException {
  const ApiTokenNotFoundException({required this.id});

  final String id;

  @override
  String toString() => 'No API token with id "$id"';
}

/// A valid API token was presented to an endpoint that does not take one.
///
/// API tokens are for the data API. Everything else -- `/auth/*`, `/admin/*`,
/// `/maintenance/*`, `/cron/*`, `/email/*`, `/push/*`, photos -- refuses one,
/// and refuses by **default**: `_extractJwt` denies unless the call site opts
/// in, so a path added later and forgotten fails closed rather than quietly
/// accepting a never-expiring credential.
///
/// The reason those endpoints are not merely scoped: an API token's scope is
/// expressed in tables and operations, which is a vocabulary none of them
/// have. A token "scoped to orders" has no meaningful answer to "may it purge
/// an internal table" or "may it invite an admin", and inventing one per
/// endpoint is how a scope stops meaning anything.
final class ApiTokenNotAcceptedHereException extends ApiTokenException {
  const ApiTokenNotAcceptedHereException();

  @override
  String toString() =>
      'An API token is not accepted here. API tokens authenticate the data '
      'API; sign in for anything else.';
}
