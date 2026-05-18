/// Server entry: pre-renders [Document] and [App] for each request.
library;

import 'package:jaspr/server.dart';
import 'package:zonai_schema/payloads.dart';

import 'app.dart';
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
      body: AsyncBuilder(
        builder: (context) async {
          final tables = loadZonaiSqliteTableNames();
          final signedIn = context.cookies[ZonaiCookie.signedIn.key] == '1';
          final authTypes = signedIn ? <AuthType>[] : await loadSupportedAuthTypes();
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
