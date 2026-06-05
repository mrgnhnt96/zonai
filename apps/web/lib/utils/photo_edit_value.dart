import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:zonai_schema/payloads.dart';

const _photoIdSuffix = 'ph';
/// One image in a photo column draft (existing id or not-yet-uploaded bytes).
sealed class PhotoEditItem {
  const PhotoEditItem();

  /// Resolved photo id (from list URL or raw id).
  const factory PhotoEditItem.existing({
    required String id,
    String? previewUrl,
  }) = PhotoEditExistingItem;

  /// Local file selected but not uploaded yet.
  const factory PhotoEditItem.pending({
    required Uint8List bytes,
    required String mimeType,
    String? replaceId,
  }) = PhotoEditPendingItem;

  bool get isPending => this is PhotoEditPendingItem;
  bool get isExisting => this is PhotoEditExistingItem;

  String? get existingId => switch (this) {
    PhotoEditExistingItem(:final id) => id,
    PhotoEditPendingItem(:final replaceId?) => replaceId,
    PhotoEditPendingItem() => null,
  };

  String? get previewUrl => switch (this) {
    PhotoEditExistingItem(:final previewUrl) => previewUrl,
    _ => null,
  };
}

final class PhotoEditExistingItem extends PhotoEditItem {
  const PhotoEditExistingItem({required this.id, this.previewUrl});

  final String id;
  final String? previewUrl;
}

final class PhotoEditPendingItem extends PhotoEditItem {
  const PhotoEditPendingItem({
    required this.bytes,
    required this.mimeType,
    this.replaceId,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? replaceId;
}

/// Draft value for [ColumnShapeKind.photo] or [ColumnShapeKind.photos].
sealed class PhotoEditValue {
  const PhotoEditValue();

  const factory PhotoEditValue.single(PhotoEditItem? item) = PhotoEditSingleValue;

  const factory PhotoEditValue.multi(List<PhotoEditItem> items) = PhotoEditMultiValue;

  bool get hasPending => switch (this) {
    PhotoEditSingleValue(:final item) => item?.isPending ?? false,
    PhotoEditMultiValue(:final items) => items.any((i) => i.isPending),
  };

  bool get isEmpty => switch (this) {
    PhotoEditSingleValue(:final item) => item == null,
    PhotoEditMultiValue(:final items) => items.isEmpty,
  };
}

final class PhotoEditSingleValue extends PhotoEditValue {
  const PhotoEditSingleValue(this.item);

  final PhotoEditItem? item;
}

final class PhotoEditMultiValue extends PhotoEditValue {
  const PhotoEditMultiValue(this.items);

  final List<PhotoEditItem> items;
}

bool isPhotoColumnKind(ColumnShapeKind kind) =>
    kind == ColumnShapeKind.photo || kind == ColumnShapeKind.photos;

/// True when [raw] is a photo id, image URL, or list of those.
bool cellLooksLikePhoto(Object? raw) {
  if (raw == null) return false;
  if (raw is List) {
    if (raw.isEmpty) return false;
    return raw.any(cellLooksLikePhoto);
  }
  return parsePhotoIdFromCell('$raw') != null;
}

ColumnShapeKind _inferredPhotoKind(Object? raw) =>
    raw is List ? ColumnShapeKind.photos : ColumnShapeKind.photo;

/// Shape to use when rendering or copying a photo cell.
///
/// Returns [shape] when it is already a photo column, otherwise upgrades a
/// text-like shape when [rawValue] looks like a resolved photo field.
ColumnShape? photoShapeForCell({
  required ColumnShape? shape,
  required Object? rawValue,
}) {
  if (shape != null && isPhotoColumnKind(shape.kind)) return shape;
  if (!cellLooksLikePhoto(rawValue)) return null;

  final base =
      shape ??
      ColumnShape(
        name: 'photo',
        kind: _inferredPhotoKind(rawValue),
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );

  if (isPhotoColumnKind(base.kind)) return base;

  return ColumnShape(
    name: base.name,
    kind: _inferredPhotoKind(rawValue),
    isNullable: base.isNullable,
    isPrimaryKey: base.isPrimaryKey,
    autoIncrement: base.autoIncrement,
    sqlType: base.sqlType,
    defaultValue: base.defaultValue,
    foreignKey: base.foreignKey,
    enumValues: base.enumValues,
    isSecret: base.isSecret,
    isReadOnly: base.isReadOnly,
  );
}

/// Empty draft for a photo column shape.
PhotoEditValue emptyPhotoEditValue(ColumnShape shape) {
  return switch (shape.kind) {
    ColumnShapeKind.photo => const PhotoEditValue.single(null),
    ColumnShapeKind.photos => const PhotoEditValue.multi([]),
    _ => throw ArgumentError('Not a photo column: ${shape.kind}'),
  };
}

/// Builds a [PhotoEditValue] from a list/URL cell when entering edit mode.
PhotoEditValue photoEditValueFromCell(Object? raw, ColumnShape shape) {
  return switch (shape.kind) {
    ColumnShapeKind.photo => PhotoEditValue.single(_itemFromCell(raw)),
    ColumnShapeKind.photos => PhotoEditValue.multi(_itemsFromCell(raw)),
    _ => throw ArgumentError('Not a photo column: ${shape.kind}'),
  };
}

PhotoEditItem? _itemFromCell(Object? raw) {
  if (raw == null) return null;
  final text = '$raw'.trim();
  if (text.isEmpty) return null;
  final id = parsePhotoIdFromCell(text);
  if (id == null) return null;
  final previewUrl = text.contains('/img/') ? text : null;
  return PhotoEditItem.existing(id: id, previewUrl: previewUrl);
}

List<PhotoEditItem> _itemsFromCell(Object? raw) {
  if (raw == null) return const [];

  if (raw is List) {
    return [
      for (final item in raw)
        if (item != null) _itemFromCell(item),
    ].whereType<PhotoEditItem>().toList();
  }

  final text = '$raw'.trim();
  if (text.isEmpty) return const [];
  if (text.startsWith('[')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return [
          for (final item in decoded)
            if (item != null) _itemFromCell(item),
        ].whereType<PhotoEditItem>().toList();
      }
    } on FormatException {
      // fall through
    }
  }

  final single = _itemFromCell(raw);
  return single == null ? const [] : [single];
}

/// Extracts a photo id from a resolved image URL or raw id string.
String? parsePhotoIdFromCell(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final imgIndex = trimmed.indexOf('/img/');
  if (imgIndex >= 0) {
    final after = trimmed.substring(imgIndex + 5);
    final path = after.split('?').first;
    final segment = path.split('/').first;
    final dot = segment.lastIndexOf('.');
    final id = dot > 0 ? segment.substring(0, dot) : segment;
    if (id.endsWith(_photoIdSuffix)) return id;
    return null;
  }

  if (trimmed.endsWith(_photoIdSuffix)) return trimmed;
  return null;
}

/// Photo ids currently referenced by a draft (excludes pending without replaceId).
List<String> photoEditValueIds(PhotoEditValue? value) {
  if (value == null) return const [];

  return switch (value) {
    PhotoEditSingleValue(:final item) => [
      if (item case PhotoEditExistingItem(:final id)) id,
      if (item case PhotoEditPendingItem(:final replaceId?) when replaceId.isNotEmpty) replaceId,
    ],
    PhotoEditMultiValue(:final items) => [
      for (final item in items)
        if (item case PhotoEditExistingItem(:final id)) id,
    ],
  };
}

/// Image URLs from a stored row cell (full URLs or ids resolved via [imageBaseUrl]).
List<String> photoUrlsFromCell(
  Object? raw,
  ColumnShape shape, {
  required String imageBaseUrl,
}) {
  final urls = <String>[];

  void addUrl(Object? item) {
    if (item == null) return;
    final text = '$item';
    if (text.startsWith('http://') || text.startsWith('https://')) {
      urls.add(text);
      return;
    }
    final id = parsePhotoIdFromCell(text);
    if (id != null) urls.add('$imageBaseUrl/img/$id');
  }

  if (shape.kind == ColumnShapeKind.photo) {
    addUrl(raw);
  } else if (raw is List) {
    for (final item in raw) {
      addUrl(item);
    }
  } else {
    addUrl(raw);
  }

  return urls;
}

/// Photo ids from a stored row cell (URLs or raw ids).
List<String> photoIdsFromCell(Object? raw, ColumnShape shape) {
  return switch (shape.kind) {
    ColumnShapeKind.photo => [
      if (_itemFromCell(raw) case PhotoEditExistingItem(:final id)) id,
    ],
    ColumnShapeKind.photos => [
      for (final item in _itemsFromCell(raw))
        if (item case PhotoEditExistingItem(:final id)) id,
    ],
    _ => const [],
  };
}

/// Ids removed when comparing an original row cell to a draft value.
Set<String> removedPhotoIds({
  required Object? originalCell,
  required PhotoEditValue? draft,
  required ColumnShape shape,
}) {
  final before = photoIdsFromCell(originalCell, shape).toSet();
  final after = photoEditValueIds(draft).toSet();
  return before.difference(after);
}

/// Whether two draft values are equal for dirty detection.
bool photoEditValuesEqual(Object? a, Object? b) {
  final va = asPhotoEditValue(a);
  final vb = asPhotoEditValue(b);
  if (va == null && vb == null) return a == b;
  if (va == null || vb == null) return false;

  return switch ((va, vb)) {
    (PhotoEditSingleValue(item: final a), PhotoEditSingleValue(item: final b)) => _itemsEqual(
      a == null ? const [] : [a],
      b == null ? const [] : [b],
    ),
    (PhotoEditMultiValue(items: final a), PhotoEditMultiValue(items: final b)) => _itemsEqual(a, b),
    _ => false,
  };
}

/// Returns [value] when it is already a [PhotoEditValue].
PhotoEditValue? asPhotoEditValue(Object? value) {
  if (value is PhotoEditValue) return value;
  return null;
}

bool _itemsEqual(List<PhotoEditItem> a, List<PhotoEditItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_itemEqual(a[i], b[i])) return false;
  }
  return true;
}

bool _itemEqual(PhotoEditItem a, PhotoEditItem b) {
  return switch ((a, b)) {
    (PhotoEditExistingItem(id: final idA), PhotoEditExistingItem(id: final idB)) => idA == idB,
    (
      PhotoEditPendingItem(bytes: final bytesA, mimeType: final mimeA, replaceId: final replaceA),
      PhotoEditPendingItem(bytes: final bytesB, mimeType: final mimeB, replaceId: final replaceB),
    ) =>
      mimeA == mimeB &&
          replaceA == replaceB &&
          const ListEquality<int>().equals(bytesA, bytesB),
    _ => false,
  };
}

/// Wire value for DB create/update after uploads (ids only).
Object? photoEditValueToWire(PhotoEditValue value) {
  return switch (value) {
    PhotoEditSingleValue(:final item) => switch (item) {
      null => null,
      PhotoEditExistingItem(:final id) => id,
      PhotoEditPendingItem() => throw StateError('Unresolved pending photo upload'),
    },
    PhotoEditMultiValue(:final items) => [
      for (final item in items)
        if (item case PhotoEditExistingItem(:final id)) id,
    ],
  };
}

/// Validates draft has required content; does not upload.
void validatePhotoDraftValue({required Object? draftValue, required ColumnShape shape}) {
  if (!isPhotoColumnKind(shape.kind)) return;

  final value = asPhotoEditValue(draftValue) ?? photoEditValueFromCell(draftValue, shape);
  if (!shape.isNullable && value.isEmpty) {
    throw FormatException('${shape.name} is required');
  }

  for (final item in _allItems(value)) {
    if (item is PhotoEditPendingItem && item.bytes.isEmpty) {
      throw FormatException('${shape.name} has an empty image');
    }
  }
}

List<PhotoEditItem> _allItems(PhotoEditValue value) {
  return switch (value) {
    PhotoEditSingleValue(:final item) => item == null ? const [] : [item],
    PhotoEditMultiValue(:final items) => items,
  };
}
