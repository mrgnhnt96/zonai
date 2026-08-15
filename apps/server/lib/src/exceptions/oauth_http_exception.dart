/// Failures that belong to the OAuth *HTTP surface* rather than to the auth
/// pipeline behind it.
///
/// These live here, not alongside `AuthException` in `apps/zonai`, because
/// nothing below ever reaches the db mutator: they are decided from the shape
/// of the callback request itself, before any challenge is consumed or any
/// code is exchanged. `AuthException` is `sealed` in another package anyway,
/// so a subtype could not live here even if the split were arbitrary.
///
/// Every message below is deliberately value-free. Design §4 item 7: a
/// `code`, a `state` or a token must never reach an error message — and an
/// error message is the one place a 4xx body puts arbitrary text in front of
/// the caller *and* into `Trace`'s error log.
sealed class OAuthHttpException implements Exception {
  const OAuthHttpException();
}

/// The provider itself rejected the authorization request and redirected
/// back with `?error=` instead of a code — the user cancelled, the client is
/// misconfigured, consent was withheld (RFC 6749 §4.1.2.1).
///
/// [error] is the provider's short error *code* (`access_denied`,
/// `invalid_scope`, …). The accompanying `error_description` is deliberately
/// dropped rather than echoed: it is free text under the provider's control,
/// and reflecting it into our response body makes the provider an author of
/// our error page.
final class OAuthProviderRejectedException extends OAuthHttpException {
  const OAuthProviderRejectedException({
    required this.provider,
    required this.error,
    this.redirectTo,
  });

  final String provider;
  final String error;

  /// Where the flow said to land when it started, recovered from *our own*
  /// challenge row by `ZonaiDb.abandonOAuth` — never a value the provider
  /// supplied, and only ever one `_isAllowedOAuthRedirect` already approved
  /// (design §4 item 5).
  ///
  /// `null` when the callback carried no usable `state`, or none matched a
  /// consumable challenge. There is then no destination this server can
  /// justify, and the route answers 400 instead of guessing.
  final String? redirectTo;

  @override
  String toString() =>
      'OAuth provider "$provider" rejected the request: $error';
}

/// The callback arrived with neither a provider error nor a usable
/// `code`+`state` pair.
///
/// Reported as which of the two was present, never their values — the whole
/// point of this type over a null cast, which would have surfaced as a 500
/// and put the raw request in the log.
final class OAuthCallbackIncompleteException extends OAuthHttpException {
  const OAuthCallbackIncompleteException({
    required this.provider,
    required this.hasCode,
    required this.hasState,
  });

  final String provider;
  final bool hasCode;
  final bool hasState;

  @override
  String toString() {
    final missing = [if (!hasCode) 'code', if (!hasState) 'state'];
    return 'OAuth callback for "$provider" is missing: ${missing.join(', ')}';
  }
}
