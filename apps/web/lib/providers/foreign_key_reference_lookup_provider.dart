import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import 'app_base_url_provider.dart';
import 'foreign_key_rows_provider.dart';
import 'table_schema_provider.dart';

/// Parameters for [foreignKeyReferenceLookupProvider].
final class ForeignKeyReferenceLookupQuery {
  const ForeignKeyReferenceLookupQuery({required this.foreignKey, required this.rawValue});

  final ForeignKeyShape foreignKey;
  final Object rawValue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForeignKeyReferenceLookupQuery && foreignKey == other.foreignKey && rawValue == other.rawValue;

  @override
  int get hashCode => Object.hash(foreignKey, rawValue);
}

/// Loads the referenced row and display label for a FK cell in the home table.
final foreignKeyReferenceLookupProvider =
    FutureProvider.family<ForeignKeyReferencedRow?, ForeignKeyReferenceLookupQuery>((ref, query) async {
      if (!ref.binding.isClient) return null;

      final schema = ref.watch(tableSchemasProvider)[query.foreignKey.table];
      return loadForeignKeyReferencedRow(
        server: ref.read(revaliServerProvider),
        imageBaseUrl: ref.read(appBaseUrlProvider),
        foreignKey: query.foreignKey,
        parsedValue: query.rawValue,
        schema: schema,
      );
    });
