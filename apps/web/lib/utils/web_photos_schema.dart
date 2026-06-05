import 'package:zonai_schema/payloads.dart';

/// Internal `_photos` table name in SQLite.
const photosTableSqliteName = '_photos';

/// Web-only column showing the resolved image URL for a photo row.
const photosImageColumnName = 'image';

const photosImageColumnShape = ColumnShape(
  name: photosImageColumnName,
  kind: ColumnShapeKind.photo,
  isNullable: true,
  isPrimaryKey: false,
  autoIncrement: false,
  sqlType: 'TEXT',
  isReadOnly: true,
);

/// Builds `$imageBaseUrl/img/<id>.png` for a photo row id.
String? photoImageUrlFromId(Object? id, {required String imageBaseUrl, required Object? extension}) {
  if (id == null) return null;
  final text = '$id'.trim();
  if (text.isEmpty) return null;

  final normalizedBase = imageBaseUrl.endsWith('/') ? imageBaseUrl.substring(0, imageBaseUrl.length - 1) : imageBaseUrl;
  return '$normalizedBase/img/$text.${extension ?? 'png'}';
}

Map<String, Object?> augmentPhotosRowItem(Map<String, Object?> item, {required String imageBaseUrl}) {
  return {
    ...item,
    photosImageColumnName: photoImageUrlFromId(item['id'], imageBaseUrl: imageBaseUrl, extension: item['extension']),
  };
}

List<Map<String, Object?>> augmentPhotosRowItems({
  required String sqliteName,
  required List<Map<String, Object?>> items,
  required String imageBaseUrl,
}) {
  if (sqliteName != photosTableSqliteName) return items;
  return [for (final item in items) augmentPhotosRowItem(item, imageBaseUrl: imageBaseUrl)];
}

TableSchemaShape augmentPhotosTableSchema(TableSchemaShape shape) {
  if (shape.table != photosTableSqliteName) return shape;
  if (shape.columnNamed(photosImageColumnName) != null) return shape;

  final columns = [...shape.columns];
  final idIndex = columns.indexWhere((c) => c.name == 'id');
  if (idIndex >= 0) {
    columns.insert(idIndex + 1, photosImageColumnShape);
  } else {
    columns.add(photosImageColumnShape);
  }

  return TableSchemaShape(table: shape.table, columns: columns);
}

/// Applies web-only schema augmentations (e.g. `_photos.image`).
Map<String, TableSchemaShape> augmentWebSchemaShapes(Map<String, TableSchemaShape> shapes) {
  return {for (final entry in shapes.entries) entry.key: augmentPhotosTableSchema(entry.value)};
}
