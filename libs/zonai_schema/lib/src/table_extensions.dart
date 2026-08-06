import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/src/column_types/created_at_column.dart';
import 'package:zonai_schema/src/column_types/create_primary_key.dart';
import 'package:zonai_schema/src/column_types/updated_at_column.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';
import 'package:zonai_schema/src/transformers/server_generated_transformer.dart';

extension TableExtensions<S extends rd.Schema<R>, R> on rd.TableMeta<S, R> {
  R safeCreate(Map<String, dynamic> data) {
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
        case SecretTransformer() || ServerGeneratedTransformer():
          if (!mutable.containsKey(column.name)) {
            mutable[column.name] = column.isNullable ? null : '';
          }
        default:
          break;
      }
    }

    return create(mutable);
  }
}
