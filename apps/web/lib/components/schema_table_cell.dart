import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../utils/photo_edit_value.dart';
import '../utils/table_cell_edit.dart';
import 'schema_table_foreign_key_cell.dart';
import 'schema_table_photo_cell.dart';
import 'theme/theme_components.dart';

/// Renders a table body cell with rich widgets for enums, lists, and booleans.
class SchemaTableCell extends StatelessComponent {
  const SchemaTableCell({required this.rawValue, this.shape, super.key});

  final Object? rawValue;
  final ColumnShape? shape;

  static bool usesRichLayout(ColumnShape? shape, [Object? rawValue]) {
    if (shape == null) return rawValue != null && cellLooksLikePhoto(rawValue);
    if (isForeignKeyColumn(shape)) return true;
    if (isPhotoColumnKind(shape.kind) || cellLooksLikePhoto(rawValue)) return true;
    return switch (shape.kind) {
      ColumnShapeKind.list ||
      ColumnShapeKind.enum_ ||
      ColumnShapeKind.enumList ||
      ColumnShapeKind.boolean ||
      ColumnShapeKind.isVerified => true,
      _ => false,
    };
  }

  @override
  Component build(BuildContext context) {
    if (rawValue == null || shape?.isSecret == true || shape?.kind == ColumnShapeKind.password) {
      return .text(formatSchemaCell(rawValue, shape));
    }

    if (shape != null && isForeignKeyColumn(shape!)) {
      return SchemaTableForeignKeyCell(rawValue: rawValue, shape: shape!);
    }

    final photoShape = photoShapeForCell(shape: shape, rawValue: rawValue);
    if (photoShape != null) {
      return SchemaTablePhotoCell(rawValue: rawValue, shape: photoShape);
    }

    return switch (shape?.kind) {
      ColumnShapeKind.list => _listValue(rawValue),
      ColumnShapeKind.enum_ => _enumValue(rawValue, shape!.enumValues),
      ColumnShapeKind.enumList => _enumListValue(rawValue, shape!.enumValues),
      ColumnShapeKind.boolean || ColumnShapeKind.isVerified => ZonaiBooleanCheck(
        checked: cellEditValueAsBool(rawValue),
      ),
      _ => .text(formatSchemaCell(rawValue, shape)),
    };
  }

  Component _listValue(Object? value) {
    final items = cellValueAsStringList(value);
    if (items.isEmpty) return .text('—');
    return ZonaiTagList(tags: items);
  }

  Component _enumValue(Object? value, List<String> enumValues) {
    final items = cellValueAsStringList(value, enumValues);
    if (items.isEmpty) return .text('—');
    if (items.length == 1) return ZonaiEnumChip(label: items.first);
    return ZonaiEnumChipRow(values: items);
  }

  Component _enumListValue(Object? value, List<String> enumValues) {
    final items = cellValueAsStringList(value, enumValues);
    if (items.isEmpty) return .text('—');
    return ZonaiEnumChipRow(values: items);
  }
}
