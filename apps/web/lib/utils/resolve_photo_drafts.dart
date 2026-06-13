import 'package:zonai_schema/payloads.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_web/api/photo_client.dart';
import 'package:zonai_web/utils/photo_edit_value.dart';

/// Uploads pending images and returns a draft row with wire-ready photo values.
Future<List<Object?>> resolvePhotoDrafts({
  required ZonaiClient client,
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

    resolved[i] = await _resolvePhotoEditValue(client: client, sqliteName: sqliteName, value: value, config: photosConfig);
  }

  return resolved;
}

Future<Object?> _resolvePhotoEditValue({
  required ZonaiClient client,
  required String sqliteName,
  required PhotoEditValue value,
  required PhotosConfig config,
}) async {
  return switch (value) {
    PhotoEditSingleValue(:final item) =>
      await _resolveItem(client: client, sqliteName: sqliteName, item: item, config: config),
    PhotoEditMultiValue(:final items) => [
      for (final item in items)
        if (await _resolveItem(client: client, sqliteName: sqliteName, item: item, config: config) case final id?) id,
    ],
  };
}

Future<String?> _resolveItem({
  required ZonaiClient client,
  required String sqliteName,
  required PhotoEditItem? item,
  required PhotosConfig config,
}) async {
  if (item == null) return null;

  return switch (item) {
    PhotoEditExistingItem(:final id) => id,
    PhotoEditPendingItem(:final bytes, :final mimeType, :final replaceId) => () async {
      if (replaceId != null && replaceId.isNotEmpty) {
        await patchPhoto(client: client, id: replaceId, bytes: bytes, mimeType: mimeType, config: config);
        return replaceId;
      }
      return createPhoto(client: client, table: sqliteName, bytes: bytes, mimeType: mimeType, config: config);
    }(),
  };
}

/// Best-effort delete for photo ids removed from a row during edit.
///
/// Call after [resolvePhotoDrafts] so [resolvedDraft] holds wire-ready ids.
Future<void> deleteRemovedPhotos({
  required ZonaiClient client,
  required List<Object?> originalRow,
  required List<Object?> resolvedDraft,
  required List<ColumnShape> columnShapes,
}) async {
  for (var i = 0; i < columnShapes.length; i++) {
    final shape = columnShapes.elementAtOrNull(i);
    if (shape == null || !isPhotoColumnKind(shape.kind)) continue;

    final before = photoIdsFromCell(originalRow.elementAtOrNull(i), shape).toSet();
    final after = photoIdsFromCell(resolvedDraft.elementAtOrNull(i), shape).toSet();

    for (final id in before.difference(after)) {
      await deletePhotoBestEffort(client: client, id: id);
    }
  }
}
