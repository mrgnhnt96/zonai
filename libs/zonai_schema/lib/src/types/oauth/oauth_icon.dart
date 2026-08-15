/// An icon for a custom provider's sign-in button.
///
/// Built-in providers don't set one of these — the dashboard resolves their
/// icon from [OAuthProviderKind] against its own bundled brand marks
/// instead, so a compromised or unreachable icon URL can never substitute
/// itself for a well-known provider's logo.
sealed class OAuthIcon {
  const OAuthIcon();

  const factory OAuthIcon.url(String url) = OAuthIconUrl;

  const factory OAuthIcon.svg(String svg) = OAuthIconSvg;
}

/// An icon fetched from [url] at render time.
final class OAuthIconUrl extends OAuthIcon {
  const OAuthIconUrl(this.url);

  final String url;
}

/// An icon embedded as inline SVG markup, rendered without a network
/// request.
final class OAuthIconSvg extends OAuthIcon {
  const OAuthIconSvg(this.svg);

  final String svg;
}
