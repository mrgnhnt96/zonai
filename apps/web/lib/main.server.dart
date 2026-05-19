/// Server entry: pre-renders [Document] and [App] for each request.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'app.dart';
import 'constants/theme.dart';
import 'auth/auth_routes.dart';
import 'main.server.options.dart';
import 'server/sqlite_table_names.dart';
import 'server/supported_auth_types.dart';
import 'utils/zonai_cookie.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    Document(
      title: 'Zonai — Sign in',
      head: [
        script(content: themeBootstrapScript),
      ],
      body: AsyncBuilder(
        builder: (context) async {
          final tables = loadZonaiSqliteTableNames();
          final token = context.cookies[ZonaiCookie.authToken.key];
          final signedIn = token != null && token.isNotEmpty;
          // Always load so sign-out after an authenticated refresh still has auth types.
          final authTypes = await loadSupportedAuthTypes();
          final initialPath = AuthRoutes.normalizePath(context.url);
          return App(
            initialSqliteNames: tables.sqliteNames,
            initialDisplayNames: tables.displayNames,
            tablesLoadError: tables.error,
            initialSignedIn: signedIn,
            initialPath: initialPath,
            initialAuthTypes: authTypes,
          );
        },
      ),
    ),
  );
}
