/// Which built-in provider produced an [OAuthProvider], or [custom] for one
/// built by `OAuthProvider.custom(...)`. The dashboard uses this to pick a
/// bundled brand icon instead of trusting a caller-supplied one.
enum OAuthProviderKind {
  google,
  apple,
  github,
  microsoft,
  facebook,
  discord,
  gitlab,
  linkedin,
  custom,
}
