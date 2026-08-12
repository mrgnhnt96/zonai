import 'package:jaspr_riverpod/jaspr_riverpod.dart';

/// URL the brand mark is served from when a project supplies one.
///
/// Kept in sync with `server/brand_logo.dart`, which cannot be imported here —
/// that library pulls in `dart:io` through `package:zonai`.
const brandLogoUrl = '/logo.png';

/// Whether `<imagesPath>/logo.png` exists, seeded during SSR.
///
/// `false` selects the app-name letter tile, which is the default look.
final hasBrandLogoProvider = Provider<bool>((ref) => false);
