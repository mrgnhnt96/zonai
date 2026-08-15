/// Server entry: pre-renders [Document] and [App] for each request.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'app.dart';
import 'constants/theme.dart';
import 'auth/auth_routes.dart';
import 'main.server.options.dart';
import 'server/app_config.dart';
import 'server/brand_logo.dart';
import 'server/oauth_providers.dart';
import 'server/session_auth.dart';
import 'server/ssr_auth_cookie.dart';
import 'server/sqlite_table_names.dart';
import 'server/supported_auth_types.dart';
import 'server/table_collection_actions.dart';
import 'server/table_schema_shapes.dart';
import 'utils/zonai_cookie.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    Document(
      head: [
        script(content: themeBootstrapScript),
        meta(name: 'viewport', content: 'width=device-width, initial-scale=1'),
      ],
      body: AsyncBuilder(
        builder: (context) async {
          final tables = loadZonaiSqliteTableNames();
          final schemaShapes = await loadTableSchemaShapes();
          final token = context.cookies[ZonaiCookie.authToken.key];
          final session = await resolveSsrSession(token);
          if (session.clearAuthCookie) {
            clearAuthCookie(context);
          }
          final signedIn = ssrShowsSignedInShell(session, token);
          final collectionActions = signedIn ? await loadTableCollectionActions(authToken: token) : const {};
          // Always load so sign-out after an authenticated refresh still has auth types.
          final authTypes = await loadSupportedAuthTypes();
          // Same reasoning, and the same reason it is not fetched client-side:
          // a provider list present at SSR but absent at hydration is a tree
          // mismatch.
          final oauthProviders = await loadOAuthProviders();
          final appConfig = await loadAppConfig();
          final hasBrandLogo = await loadHasBrandLogo();
          final initialPath = AuthRoutes.normalizePath(context.url);
          return App(
            appConfig: appConfig,
            hasBrandLogo: hasBrandLogo,
            initialSqliteNames: tables.sqliteNames,
            initialDisplayNames: tables.displayNames,
            tablesLoadError: tables.error,
            initialSchemaShapes: {for (final e in schemaShapes.entries) e.key: e.value.toJson()},
            initialCollectionActions: {for (final e in collectionActions.entries) e.key: e.value.toJson()},
            initialSignedIn: signedIn,
            initialPath: initialPath,
            initialAuthTypes: authTypes,
            initialOAuthProviders: oauthProviders,
          );
        },
      ),
    ),
  );
}
