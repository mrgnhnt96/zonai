import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/column_types/created_at_column.dart';
import 'package:zonai_schema/src/column_types/create_primary_key.dart';
import 'package:zonai_schema/src/column_types/updated_at_column.dart';

extension TableExtensions<T extends Schema<dynamic>> on Table<dynamic> {
  dynamic safeCreate(Map<String, dynamic> data) {
    final mutable = {...data};
    for (final column in columns) {
      switch (column.transformer) {
        case final CreatedAtTransformer transformer:
          mutable[column.name] = transformer.encode(.now());
        case final UpdatedAtTransformer transformer:
          if (column.isNullable) {
            mutable[column.name] = null;
          } else {
            mutable[column.name] = transformer.encode(.now());
          }
        case final CreatePrimaryKey transformer:
          if (column.autoIncrement) continue;
          if (!column.isPrimaryKey) continue;
          mutable[column.name] ??= transformer.encodedPrimaryKey();
        default:
          break;
      }
    }

    return create(mutable);
  }
}
