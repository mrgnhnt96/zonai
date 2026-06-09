import 'package:jaspr_riverpod/jaspr_riverpod.dart';

/// Fallback when SSR does not override [appBaseUrlProvider].
///
/// Matches [AppConfig.baseUrl] default in zonai_schema.
const defaultAppBaseUrl = 'http://localhost:8080';

/// Public app URL from [AppConfig.baseUrl], seeded during SSR.
final appBaseUrlProvider = Provider<String>((ref) => defaultAppBaseUrl);
