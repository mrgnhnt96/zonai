import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/photo_client.dart';
import 'package:zonai_web/utils/photo_edit_value.dart';

/// Uploads pending images and returns a draft row with wire-ready photo values.
Future<List<Object?>> resolvePhotoDrafts({
  required String sqliteName,
  required List<Object?> draft,
  required List<ColumnShape> columnShapes,
  required PhotosConfig photosConfig,
}) async {
  final resolved = List<Object?>.from(draft);

  for (var i = 0; i < columnShapes.length; i++) {
    final shape = columnShapes.elementAtOrNull(i);
    if (shape == null || !isPhotoColumnKind(shape.kind)) continue;

    final value = asPhotoEditValue(resolved[i]);
    if (value == null) continue;

    resolved[i] = await _resolvePhotoEditValue(
      sqliteName: sqliteName,
      value: value,
      config: photosConfig,
    );
  }

  return resolved;
}

Future<Object?> _resolvePhotoEditValue({
  required String sqliteName,
  required PhotoEditValue value,
  required PhotosConfig config,
}) async {
  return switch (value) {
    PhotoEditSingleValue(:final item) => await _resolveItem(sqliteName: sqliteName, item: item, config: config),
    PhotoEditMultiValue(:final items) => [
      for (final item in items)
        if (await _resolveItem(sqliteName: sqliteName, item: item, config: config) case final id?) id,
    ],
  };
}

Future<String?> _resolveItem({
  required String sqliteName,
  required PhotoEditItem? item,
  required PhotosConfig config,
}) async {
  if (item == null) return null;

  return switch (item) {
    PhotoEditExistingItem(:final id) => id,
    PhotoEditPendingItem(:final bytes, :final mimeType, :final replaceId) => () async {
      if (replaceId != null && replaceId.isNotEmpty) {
        await patchPhoto(id: replaceId, bytes: bytes, mimeType: mimeType, config: config);
        return replaceId;
      }
      return createPhoto(table: sqliteName, bytes: bytes, mimeType: mimeType, config: config);
    }(),
  };
}

/// Best-effort delete for photo ids removed from a row during edit.
Future<void> deleteRemovedPhotos({
  required List<Object?> originalRow,
  required List<Object?> resolvedDraft,
  required List<ColumnShape> columnShapes,
}) async {
  for (var i = 0; i < columnShapes.length; i++) {
    final shape = columnShapes.elementAtOrNull(i);
    if (shape == null || !isPhotoColumnKind(shape.kind)) continue;

    final draftValue = asPhotoEditValue(resolvedDraft.elementAtOrNull(i));
    final removed = removedPhotoIds(
      originalCell: originalRow.elementAtOrNull(i),
      draft: draftValue,
      shape: shape,
    );

    for (final id in removed) {
      await deletePhotoBestEffort(id);
    }
  }
}
