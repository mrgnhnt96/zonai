import 'package:zonai_schema/src/types/oauth/oauth_icon.dart';

/// Presentation for a provider's sign-in button. Every field is optional —
/// the dashboard falls back to a bundled icon (built-ins) or a letter tile
/// (custom providers without an icon) and to its own default button colors.
final class OAuthBrand {
  const OAuthBrand({this.icon, this.background, this.foreground});

  final OAuthIcon? icon;

  /// Button fill color, e.g. `'#1877F2'`.
  final String? background;

  /// Button text/icon color, e.g. `'#FFFFFF'`.
  final String? foreground;
}
