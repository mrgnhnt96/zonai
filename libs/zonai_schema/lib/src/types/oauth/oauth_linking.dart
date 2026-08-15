/// How an OAuth sign-in resolves to an existing row in the auth table when
/// `(table, provider, subject)` has never been seen before.
enum OAuthLinking {
  /// Link to an existing row whose email matches, but only when the
  /// provider asserts that email as verified. Default.
  byVerifiedEmail,

  /// Never link by email — an unrecognized subject always provisions a new
  /// row (or is rejected by the provisioning gate).
  never,

  /// Link to an existing row whose email matches even if the provider does
  /// not assert it as verified.
  ///
  /// An account-takeover footgun: anyone who controls an email address can
  /// sign in as the row that owns it, without proving they control the
  /// inbox. Only use this against a provider that guarantees verified
  /// emails out of band.
  always,
}
