import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import '../app.dart';
import '../auth/auth_routes.dart';
import '../constants/theme.dart';
import '../utils/zonai_cookie.dart';
import 'app_config.dart';
import 'sqlite_table_names.dart';
import 'supported_auth_types.dart';

/// Shared document tree for SSR rendering in compiled Revali builds.
Component buildWebAppDocument() {
  return Document(
    base: AuthRoutes.mountPath,
    head: [script(content: themeBootstrapScript)],
    body: AsyncBuilder(
      builder: (context) async {
        final tables = loadZonaiSqliteTableNames();
        final token = context.cookies[ZonaiCookie.authToken.key];
        final signedIn = token != null && token.isNotEmpty;
        final authTypes = await loadSupportedAuthTypes();
        final appConfig = await loadAppConfig();
        final initialPath = AuthRoutes.fromUrlPath(context.url);
        return App(
          appConfig: appConfig,
          initialSqliteNames: tables.sqliteNames,
          initialDisplayNames: tables.displayNames,
          tablesLoadError: tables.error,
          initialSignedIn: signedIn,
          initialPath: initialPath,
          initialAuthTypes: authTypes,
        );
      },
    ),
  );
}
