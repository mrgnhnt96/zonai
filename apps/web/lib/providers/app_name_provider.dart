import 'package:jaspr_riverpod/jaspr_riverpod.dart';

/// Fallback when SSR does not override [appNameProvider].
const defaultAppName = 'Zonai';

/// Application display name from [AppConfig], seeded during SSR.
final appNameProvider = Provider<String>((ref) => defaultAppName);
