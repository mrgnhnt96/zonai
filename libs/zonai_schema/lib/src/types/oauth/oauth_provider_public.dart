import 'package:zonai_schema/src/types/oauth/oauth_provider_kind.dart';

/// The redacted view of an [OAuthProvider] the dashboard and Dart client are
/// allowed to see — no `clientSecret`, no Apple private key, no token or
/// userinfo endpoint. Produced by [OAuthProvider.toPublic].
final class OAuthProviderPublic {
  const OAuthProviderPublic({
    required this.id,
    required this.displayName,
    required this.table,
    required this.kind,
    required this.startPath,
    this.iconUrl,
    this.iconSvg,
    this.background,
    this.foreground,
  });

  final String id;
  final String displayName;

  /// Auth collection this provider belongs to.
  final String table;

  /// `custom` for anything built with `OAuthProvider.custom(...)` — picks
  /// the bundled icon for built-ins, tells the dashboard to fall back to
  /// [iconUrl]/[iconSvg]/a letter tile otherwise.
  final OAuthProviderKind kind;

  /// Custom providers only; built-ins resolve their icon from [kind].
  final String? iconUrl;

  /// Custom providers only; built-ins resolve their icon from [kind].
  final String? iconSvg;

  final String? background;
  final String? foreground;

  /// Where the dashboard/client sends the user to begin this provider's
  /// flow, e.g. `'/auth/oauth/start/google?table=users'`.
  final String startPath;

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'table': table,
    'kind': kind.name,
    'iconUrl': iconUrl,
    'iconSvg': iconSvg,
    'background': background,
    'foreground': foreground,
    'startPath': startPath,
  };
}
