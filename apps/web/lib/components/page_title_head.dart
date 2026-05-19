import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../providers/app_name_provider.dart';
import '../providers/collection_focus_provider.dart';
import '../utils/page_title.dart';

/// Keeps `<title>` in sync with auth state and the current route.
class PageTitleHead extends StatelessComponent {
  const PageTitleHead({super.key});

  @override
  Component build(BuildContext context) {
    final appName = context.watch(appNameProvider);
    final signedIn = context.watch(authProvider);
    final path = context.watch(authRouteProvider);
    final focused = context.watch(collectionFocusProvider);

    return Document.head(
      title: PageTitle.resolve(
        appName: appName,
        signedIn: signedIn,
        path: path,
        collectionDisplayName: focused?.displayName,
      ),
    );
  }
}
