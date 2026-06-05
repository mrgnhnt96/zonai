import 'package:jaspr_riverpod/misc.dart' show Override;
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/supported_auth_types_provider.dart';
import '../providers/app_name_provider.dart';
import '../providers/photos_config_provider.dart';
import '../providers/resolved_collection_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../providers/table_schema_provider.dart';

List<Override> appShellOverrides({
  required bool initialSignedIn,
  required String initialPath,
  required String initialAppName,
  PhotosConfig? initialPhotosConfig,
  required List<AuthType> initialAuthTypes,
  SqliteTablesSnapshot? tables,
  Map<String, TableSchemaShape>? schemaShapes,
  Map<String, TableCollectionActions>? collectionActions,
}) {
  final initialActions = collectionActions ?? const {};
  return [
    sqliteTablesProvider.overrideWithValue(
      tables ?? const SqliteTablesSnapshot(tables: []),
    ),
    tableSchemasProvider.overrideWithValue(schemaShapes ?? const {}),
    tableCollectionActionsOverride(initialActions),
    authProvider.overrideWith(() => AuthNotifier(initialSignedIn: initialSignedIn)),
    authRouteProvider.overrideWith(() => AuthRouteNotifier(initialPath: initialPath)),
    supportedAuthTypesProvider.overrideWithValue(initialAuthTypes),
    appNameProvider.overrideWithValue(initialAppName),
    photosConfigProvider.overrideWithValue(initialPhotosConfig ?? defaultPhotosConfig),
  ];
}
