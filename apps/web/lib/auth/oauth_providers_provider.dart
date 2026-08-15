import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

/// Redacted OAuth providers seeded from SSR (see [AppShell] override).
///
/// Sibling of `supportedAuthTypesProvider`: empty by default so a component
/// tree built without the SSR override still renders, and overridden with the
/// real list in `appShellOverrides`.
final oauthProvidersProvider = Provider<List<OAuthProviderPublic>>((ref) => const []);
