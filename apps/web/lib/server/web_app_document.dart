import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import '../app.dart';
import '../auth/auth_routes.dart';
import '../constants/theme.dart';
import '../utils/zonai_cookie.dart';
import 'app_config.dart';
import 'sqlite_table_names.dart';
import 'supported_auth_types.dart';
import 'table_collection_actions.dart';
import 'table_schema_shapes.dart';

/// Shared document tree for SSR rendering in compiled Revali builds.
Component buildWebAppDocument() {
  return Document(
    head: [
      script(content: themeBootstrapScript),
      script(src: '${AuthRoutes.mountPath}/main.client.dart.js', defer: true),
      meta(name: 'viewport', content: 'width=device-width, initial-scale=1'),
    ],
    body: AsyncBuilder(
      builder: (context) async {
        final tables = loadZonaiSqliteTableNames();
        final schemaShapes = await loadTableSchemaShapes();
        final token = context.cookies[ZonaiCookie.authToken.key];
        final collectionActions = await loadTableCollectionActions(authToken: token);
        final signedIn = token != null && token.isNotEmpty;
        final authTypes = await loadSupportedAuthTypes();
        final appConfig = await loadAppConfig();
        final initialPath = AuthRoutes.fromUrlPath(context.url);
        return App(
          appConfig: appConfig,
          initialSqliteNames: tables.sqliteNames,
          initialDisplayNames: tables.displayNames,
          tablesLoadError: tables.error,
          initialSchemaShapes: {for (final e in schemaShapes.entries) e.key: e.value.toJson()},
          initialCollectionActions: {for (final e in collectionActions.entries) e.key: e.value.toJson()},
          initialSignedIn: signedIn,
          initialPath: initialPath,
          initialAuthTypes: authTypes,
        );
      },
    ),
  );
}
