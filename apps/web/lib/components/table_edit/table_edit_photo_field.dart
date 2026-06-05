import 'dart:async';
import 'dart:typed_data';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../../api/api_client.dart';
import '../../utils/photo_edit_value.dart';
import '../../utils/read_web_file_bytes.dart';
import '../theme/ui_styles.dart';
import '../theme/zonai_button.dart';

/// Image picker with drag-and-drop and file browse for photo columns.
class TableEditPhotoField extends StatefulComponent {
  const TableEditPhotoField({
    super.key,
    required this.id,
    required this.shape,
    required this.value,
    required this.onChanged,
    this.labelId,
    this.disabled = false,
  });

  final String id;
  final ColumnShape shape;
  final PhotoEditValue? value;
  final void Function(PhotoEditValue value) onChanged;
  final String? labelId;
  final bool disabled;

  @override
  State<TableEditPhotoField> createState() => _TableEditPhotoFieldState();
}

class _TableEditPhotoFieldState extends State<TableEditPhotoField> {
  final _objectUrls = <PhotoEditPendingItem, String>{};
  var _dragOver = false;
  String? _error;

  @override
  void dispose() {
    _revokeAllObjectUrls();
    super.dispose();
  }

  @override
  void didUpdateComponent(covariant TableEditPhotoField oldComponent) {
    super.didUpdateComponent(oldComponent);
    _syncObjectUrls();
  }

  void _revokeAllObjectUrls() {
    for (final url in _objectUrls.values) {
      web.URL.revokeObjectURL(url);
    }
    _objectUrls.clear();
  }

  void _syncObjectUrls() {
    final pending = _pendingItems(component.value);
    for (final entry in _objectUrls.entries.toList()) {
      if (!pending.contains(entry.key)) {
        web.URL.revokeObjectURL(entry.value);
        _objectUrls.remove(entry.key);
      }
    }
    for (final item in pending) {
      if (!_objectUrls.containsKey(item)) {
        final blob = web.Blob([item.bytes.toJS].toJS);
        _objectUrls[item] = web.URL.createObjectURL(blob);
      }
    }
  }

  bool get _allowMultiple => component.shape.kind == ColumnShapeKind.photos;

  List<PhotoEditItem> _items(PhotoEditValue? value) {
    if (value == null) return const [];
    return switch (value) {
      PhotoEditSingleValue(:final item) => item == null ? const [] : [item],
      PhotoEditMultiValue(:final items) => items,
    };
  }

  List<PhotoEditPendingItem> _pendingItems(PhotoEditValue? value) {
    return [
      for (final item in _items(value))
        if (item is PhotoEditPendingItem) item,
    ];
  }

  String? _previewSrc(PhotoEditItem item) {
    return switch (item) {
      PhotoEditExistingItem(previewUrl: final previewUrl, id: final id)
          when previewUrl != null && previewUrl.isNotEmpty =>
        previewUrl,
      PhotoEditExistingItem(id: final id) => '$revaliBaseUrl/img/$id',
      PhotoEditPendingItem pending => _objectUrls[pending],
    };
  }

  PhotoEditValue _currentValue() {
    return component.value ?? emptyPhotoEditValue(component.shape);
  }

  void _emit(PhotoEditValue value) {
    component.onChanged(value);
    scheduleMicrotask(() {
      if (mounted) _syncObjectUrls();
    });
  }

  void _removeAt(int index) {
    final items = List<PhotoEditItem>.from(_items(_currentValue()));
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    _applyItems(items);
  }

  void _applyItems(List<PhotoEditItem> items) {
    if (component.shape.kind == ColumnShapeKind.photo) {
      _emit(PhotoEditValue.single(items.isEmpty ? null : items.first));
      return;
    }
    _emit(PhotoEditValue.multi(items));
  }

  Future<void> _addFiles(web.FileList files) async {
    if (component.disabled) return;
    setState(() => _error = null);

    final toAdd = <PhotoEditItem>[];
    final limit = _allowMultiple ? files.length : 1;

    for (var i = 0; i < limit; i++) {
      final file = files.item(i);
      if (file == null) continue;

      try {
        final bytes = await readWebFileBytes(file);
        final mime = _mimeForFile(file, bytes);
        if (mime == null) {
          setState(() => _error = 'Unsupported image type');
          return;
        }
        toAdd.add(PhotoEditItem.pending(bytes: bytes, mimeType: mime.mimeType));
      } on Object catch (e) {
        setState(() => _error = e.toString());
        return;
      }
    }

    if (toAdd.isEmpty) return;

    if (_allowMultiple) {
      final existing = List<PhotoEditItem>.from(_items(_currentValue()));
      existing.addAll(toAdd);
      _applyItems(existing);
      return;
    }

    final replaceId = switch (_currentValue()) {
      PhotoEditSingleValue(:final item) => switch (item) {
        PhotoEditExistingItem(:final id) => id,
        PhotoEditPendingItem(:final replaceId) => replaceId,
        _ => null,
      },
      _ => null,
    };

    final pending = toAdd.first;
    if (pending is PhotoEditPendingItem && replaceId != null) {
      _emit(PhotoEditValue.single(
        PhotoEditItem.pending(
          bytes: pending.bytes,
          mimeType: pending.mimeType,
          replaceId: replaceId,
        ),
      ));
      return;
    }

    _emit(PhotoEditValue.single(toAdd.first));
  }

  ImageMimeType? _mimeForFile(web.File file, Uint8List bytes) {
    final fromType = ImageMimeType.fromContentType(file.type);
    if (fromType != null) return fromType;
    return ImageMimeType.detect(bytes);
  }

  void _onBrowseClick() {
    if (component.disabled) return;
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/*';
    if (_allowMultiple) input.multiple = true;
    input.onChange.listen((_) async {
      final files = input.files;
      if (files == null || files.length == 0) return;
      await _addFiles(files);
      input.remove();
    });
    input.click();
  }

  void _onDragOver(web.Event event) {
    event.preventDefault();
    if (component.disabled) return;
    setState(() => _dragOver = true);
  }

  void _onDragLeave(web.Event event) {
    event.preventDefault();
    setState(() => _dragOver = false);
  }

  Future<void> _onDrop(web.Event event) async {
    event.preventDefault();
    setState(() => _dragOver = false);
    if (component.disabled) return;

    if (event is! web.DragEvent) return;
    final files = event.dataTransfer?.files;
    if (files == null || files.length == 0) return;
    await _addFiles(files);
  }

  @override
  Component build(BuildContext context) {
    final items = _items(_currentValue());
    final inputId = '${component.id}-file';
    final zoneClass = [
      'table-edit-photo-field__zone',
      if (_dragOver) 'table-edit-photo-field__zone--active',
      if (component.disabled) 'table-edit-photo-field__zone--disabled',
    ].join(' ');

    return div(classes: 'table-edit-photo-field', [
      if (items.isNotEmpty)
        div(classes: 'table-edit-photo-field__thumbs', [
          for (var i = 0; i < items.length; i++)
            _PhotoThumb(
              src: _previewSrc(items[i]),
              label: switch (items[i]) {
                PhotoEditExistingItem(:final id) => id,
                PhotoEditPendingItem() => 'New image',
              },
              onRemove: component.disabled ? null : () => _removeAt(i),
            ),
        ]),
      div(
        classes: zoneClass,
        events: {
          'dragover': _onDragOver,
          'dragleave': _onDragLeave,
          'drop': _onDrop,
        },
        [
          p(classes: 'table-edit-photo-field__hint', [
            text(_allowMultiple ? 'Drag images here or browse' : 'Drag an image here or browse'),
          ]),
          ZonaiButton(
            variant: ZonaiButtonVariant.ghost,
            disabled: component.disabled,
            events: {
              'click': (event) {
                event.preventDefault();
                event.stopPropagation();
                _onBrowseClick();
              },
            },
            child: text('Browse…'),
          ),
          input(
            id: inputId,
            type: .file,
            attributes: {
              'accept': 'image/*',
              if (_allowMultiple) 'multiple': 'multiple',
              if (component.labelId != null) 'aria-labelledby': component.labelId!,
              'hidden': 'hidden',
            },
          ),
        ],
      ),
      if (_error != null) p(classes: 'table-edit-photo-field__error', [text(_error!)]),
    ]);
  }
}

class _PhotoThumb extends StatelessComponent {
  const _PhotoThumb({required this.src, required this.label, this.onRemove});

  final String? src;
  final String label;
  final VoidCallback? onRemove;

  @override
  Component build(BuildContext context) {
    return div(classes: 'table-edit-photo-field__thumb', [
      if (src != null)
        img(src: src!, attributes: {'alt': label, 'loading': 'lazy'})
      else
        div(classes: 'table-edit-photo-field__thumb-placeholder', [text(label)]),
      if (onRemove != null)
        button(
          type: .button,
          classes: 'table-edit-photo-field__remove',
          attributes: {'aria-label': 'Remove image'},
          events: {
            'click': (event) {
              event.preventDefault();
              event.stopPropagation();
              onRemove!();
            },
          },
          [text('×')],
        ),
    ]);
  }
}
