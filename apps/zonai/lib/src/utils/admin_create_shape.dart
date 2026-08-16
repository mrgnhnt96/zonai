import 'package:zonai_schema/payloads.dart';

import '../db_mutator/zonai_db/zonai_db.dart';

/// Columns handled by [ZonaiDb.createAdmin] auth flow (not user-supplied extras).
bool isAuthAdminHandledColumn(ColumnShape shape) {
  return switch (shape.kind) {
    ColumnShapeKind.id ||
    ColumnShapeKind.email ||
    ColumnShapeKind.password ||
    ColumnShapeKind.isVerified ||
    ColumnShapeKind.createdAt ||
    ColumnShapeKind.updatedAt => true,
    _ => false,
  };
}

/// Whether a column can be supplied when creating an admin (mirrors web create UI).
bool isAdminExtraFieldEditable(ColumnShape shape) {
  if (isAuthAdminHandledColumn(shape)) return false;
  if (shape.isPrimaryKey || shape.autoIncrement || shape.isReadOnly) {
    return false;
  }
  return true;
}

/// Extra admin columns the user may need to fill (e.g. `name` on `users`).
List<ColumnShape> adminExtraCreateFields(List<ColumnShape> columnShapes) {
  return [
    for (final shape in columnShapes)
      if (isAdminExtraFieldEditable(shape)) shape,
  ];
}

/// Whether a value must be supplied for an extra admin create field.
bool isAdminExtraFieldRequired(ColumnShape shape) {
  if (!isAdminExtraFieldEditable(shape) || shape.isNullable) return false;

  return switch (shape.kind) {
    ColumnShapeKind.boolean || ColumnShapeKind.isVerified => false,
    _ => true,
  };
}

/// Labels for required extra fields missing from [values].
List<String> missingAdminExtraFieldLabels({
  required List<ColumnShape> extraFields,
  required Map<String, String> values,
}) {
  return [
    for (final shape in extraFields)
      if (isAdminExtraFieldRequired(shape) &&
          (values[shape.name]?.trim().isEmpty ?? true))
        columnShapeHeaderLabel(shape),
  ];
}

/// Builds the `object` payload for [ZonaiDb.createAdmin] from extra field values.
Map<String, dynamic> buildAdminCreateObject({
  required List<ColumnShape> extraFields,
  required Map<String, String> values,
}) {
  final object = <String, dynamic>{};
  for (final shape in extraFields) {
    final raw = values[shape.name]?.trim();
    if (raw != null && raw.isNotEmpty) {
      object[shape.name] = parseAdminExtraFieldValue(raw, shape);
      continue;
    }

    switch (shape.kind) {
      case ColumnShapeKind.boolean:
      case ColumnShapeKind.isVerified:
        object[shape.name] = false;
      case ColumnShapeKind.list:
      case ColumnShapeKind.enumList:
        object[shape.name] = <String>[];
      default:
        break;
    }
  }
  return object;
}

/// Parses a CLI/TUI text value into the wire shape for [shape].
Object? parseAdminExtraFieldValue(String raw, ColumnShape shape) {
  return switch (shape.kind) {
    ColumnShapeKind.boolean || ColumnShapeKind.isVerified => switch (raw
        .toLowerCase()) {
      '1' || 'true' || 'yes' => true,
      '0' || 'false' || 'no' => false,
      _ => throw FormatException('Invalid boolean for "${shape.name}": $raw'),
    },
    ColumnShapeKind.integer =>
      int.tryParse(raw) ??
          (throw FormatException('Invalid integer for "${shape.name}": $raw')),
    ColumnShapeKind.real =>
      double.tryParse(raw) ??
          (throw FormatException('Invalid number for "${shape.name}": $raw')),
    ColumnShapeKind.bigInt =>
      BigInt.tryParse(raw) ??
          (throw FormatException('Invalid bigint for "${shape.name}": $raw')),
    ColumnShapeKind.enum_ =>
      shape.enumValues.contains(raw)
          ? raw
          : throw FormatException(
              'Invalid enum for "${shape.name}": $raw (expected ${shape.enumValues.join(", ")})',
            ),
    _ => raw,
  };
}

/// Resolves schema metadata for the configured admin collection, whatever
/// auth type(s) it supports.
Future<TableSchemaShape> resolveAdminTableShape(ZonaiDb db) async {
  final (table, _) = await db.adminTable();
  final shapes = await db.schemaShapes();
  final shape = shapes[table];
  if (shape == null) {
    throw StateError('No schema shape found for admin table "$table"');
  }
  return shape;
}

/// Merges explicit `--data` with shape-aware defaults for extra admin fields.
Map<String, dynamic> resolveAdminCreateObject({
  required List<ColumnShape> extraFields,
  Map<String, dynamic>? data,
}) {
  if (extraFields.isEmpty) {
    return data ?? const {};
  }

  final values = <String, String>{
    for (final entry in data?.entries ?? const <MapEntry<String, dynamic>>[])
      if (entry.value != null) entry.key: '${entry.value}',
  };

  final missing = missingAdminExtraFieldLabels(
    extraFields: extraFields,
    values: values,
  );
  if (missing.isNotEmpty) {
    throw StateError(
      'Missing required admin fields: ${missing.join(", ")}. '
      'Pass them with --data \'{"${missing.first}":"..."}\'',
    );
  }

  final object = buildAdminCreateObject(
    extraFields: extraFields,
    values: values,
  );

  if (data != null) {
    for (final entry in data.entries) {
      object.putIfAbsent(entry.key, () => entry.value);
    }
  }

  return object;
}
