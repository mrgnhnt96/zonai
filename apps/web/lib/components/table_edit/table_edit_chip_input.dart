import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';
import '../theme/zonai_button.dart';
import '../theme/zonai_tag.dart';

/// Chip list editor for comma-separated list values (row detail edit panel).
class TableEditChipInput extends StatefulComponent {
  const TableEditChipInput({
    super.key,
    required this.id,
    required this.valueText,
    required this.onValueTextChanged,
    this.placeholder = 'Add value…',
    this.labelId,
    this.disabled = false,
    this.reorderable = true,
  });

  final String id;
  final String valueText;
  final void Function(String valueText) onValueTextChanged;
  final String placeholder;
  final String? labelId;
  final bool disabled;

  /// When true (default), chips can be dragged to reorder when there are 2+ chips.
  final bool reorderable;

  @override
  State<TableEditChipInput> createState() => _TableEditChipInputState();
}

enum _ChipDropSide { left, right }

class _TableEditChipInputState extends State<TableEditChipInput> {
  var _draft = '';
  int? _dragFromIndex;
  int? _dropIndex;
  _ChipDropSide? _dropSide;
  int? _dropInsertIndex;

  @override
  void didUpdateComponent(covariant TableEditChipInput oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.valueText != component.valueText) {
      _draft = '';
      _clearDragState();
    }
  }

  List<String> get _chips => parseCommaSeparatedList(component.valueText);

  bool get _canReorderChips =>
      component.reorderable && !component.disabled && _chips.length > 1;

  void _clearDragState() {
    if (_dragFromIndex == null &&
        _dropIndex == null &&
        _dropSide == null &&
        _dropInsertIndex == null) {
      return;
    }
    setState(() {
      _dragFromIndex = null;
      _dropIndex = null;
      _dropSide = null;
      _dropInsertIndex = null;
    });
  }

  void _setChips(List<String> chips) {
    component.onValueTextChanged(joinCommaSeparatedList(chips));
  }

  void _addChip(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final chips = [..._chips];
    if (!chips.contains(trimmed)) chips.add(trimmed);
    _setChips(chips);
    setState(() => _draft = '');
  }

  void _removeChip(String chip) {
    _setChips(_chips.where((c) => c != chip).toList());
  }

  void _moveChipToInsertIndex(int from, int insertIndex) {
    final next = reorderStringListToInsertIndex(_chips, from, insertIndex);
    if (identical(next, _chips)) return;
    _setChips(next);
  }

  bool _insertWouldChangeOrder(int from, int insertIndex) {
    var to = insertIndex;
    if (from < to) to--;
    return from != to;
  }

  bool _showsDropPipe(int chipIndex, _ChipDropSide side) {
    final from = _dragFromIndex;
    if (from == null || _dropIndex != chipIndex || _dropSide != side) return false;
    final insertIndex = side == _ChipDropSide.left ? chipIndex : chipIndex + 1;
    return _insertWouldChangeOrder(from, insertIndex);
  }

  void _setDropTarget({
    required int chipIndex,
    required _ChipDropSide side,
    required int insertIndex,
  }) {
    if (_dropIndex == chipIndex && _dropSide == side && _dropInsertIndex == insertIndex) return;
    setState(() {
      _dropIndex = chipIndex;
      _dropSide = side;
      _dropInsertIndex = insertIndex;
    });
  }

  void _preventDragDefault(web.DragEvent event) {
    event.preventDefault();
    event.stopPropagation();
    final transfer = event.dataTransfer;
    if (transfer != null) transfer.dropEffect = 'move';
  }

  void _onChipDragStart(web.Event event, int index) {
    if (!_canReorderChips) return;
    if (event is! web.DragEvent) return;
    if (_dragStartedOnRemoveButton(event)) {
      event.preventDefault();
      return;
    }
    event.stopPropagation();
    final transfer = event.dataTransfer;
    if (transfer != null) {
      transfer.effectAllowed = 'move';
      transfer.setData('text/plain', '$index');
    }
    setState(() {
      _dragFromIndex = index;
      _dropIndex = null;
      _dropSide = null;
      _dropInsertIndex = null;
    });
  }

  void _onChipDragOver(web.Event event, int index) {
    if (_dragFromIndex == null) return;
    if (event is! web.DragEvent) return;
    _preventDragDefault(event);

    final current = event.currentTarget;
    if (current is! web.Element) return;
    final rect = current.getBoundingClientRect();
    final midX = rect.left + rect.width / 2;
    final side = event.clientX < midX ? _ChipDropSide.left : _ChipDropSide.right;
    final insertIndex = side == _ChipDropSide.left ? index : index + 1;
    _setDropTarget(chipIndex: index, side: side, insertIndex: insertIndex);
  }

  void _onChipsContainerDragOver(web.Event event) {
    if (_dragFromIndex == null) return;
    if (event is! web.DragEvent) return;
    _preventDragDefault(event);

    final container = event.currentTarget;
    if (container is! web.Element) return;

    final chipElements = _chipItemElements(container);
    final count = chipElements.length;
    if (count == 0) return;

    final x = event.clientX.toDouble();
    final y = event.clientY.toDouble();
    final firstRect = chipElements.first.getBoundingClientRect();
    final lastRect = chipElements.last.getBoundingClientRect();

    if (_pointerBeforeChips(x, y, firstRect)) {
      _setDropTarget(chipIndex: 0, side: _ChipDropSide.left, insertIndex: 0);
      return;
    }
    if (_pointerAfterChips(x, y, lastRect)) {
      _setDropTarget(chipIndex: count - 1, side: _ChipDropSide.right, insertIndex: count);
      return;
    }

    for (var i = 0; i < count; i++) {
      final rect = chipElements[i].getBoundingClientRect();
      if (x < rect.left || x > rect.right || y < rect.top || y > rect.bottom) continue;

      final midX = rect.left + rect.width / 2;
      final side = x < midX ? _ChipDropSide.left : _ChipDropSide.right;
      final insertIndex = side == _ChipDropSide.left ? i : i + 1;
      _setDropTarget(chipIndex: i, side: side, insertIndex: insertIndex);
      return;
    }

    final insertIndex = _insertIndexInGap(x, y, chipElements);
    final chipIndex = insertIndex == 0 ? 0 : insertIndex - 1;
    final side = insertIndex == 0 ? _ChipDropSide.left : _ChipDropSide.right;
    _setDropTarget(chipIndex: chipIndex, side: side, insertIndex: insertIndex);
  }

  bool _pointerBeforeChips(double x, double y, web.DOMRect first) {
    const margin = 8.0;
    return x < first.left - margin || y < first.top - margin;
  }

  bool _pointerAfterChips(double x, double y, web.DOMRect last) {
    const margin = 8.0;
    return x > last.right + margin || y > last.bottom + margin;
  }

  List<web.Element> _chipItemElements(web.Element container) {
    final nodes = container.querySelectorAll('.table-edit-chip-input__chip-item');
    return [
      for (var i = 0; i < nodes.length; i++) nodes.item(i)! as web.Element,
    ];
  }

  int _insertIndexInGap(double x, double y, List<web.Element> chipElements) {
    final count = chipElements.length;
    var bestIndex = count;
    var bestDistance = double.infinity;

    for (var i = 0; i <= count; i++) {
      final before = i == 0 ? null : chipElements[i - 1];
      final after = i == count ? null : chipElements[i];

      late final double slotX;
      late final double slotY;
      if (before == null && after != null) {
        final rect = after.getBoundingClientRect();
        slotX = rect.left;
        slotY = rect.top + rect.height / 2;
      } else if (before != null && after == null) {
        final rect = before.getBoundingClientRect();
        slotX = rect.right;
        slotY = rect.top + rect.height / 2;
      } else if (before != null && after != null) {
        final beforeRect = before.getBoundingClientRect();
        final afterRect = after.getBoundingClientRect();
        slotX = (beforeRect.right + afterRect.left) / 2;
        slotY =
            (beforeRect.top +
                beforeRect.height / 2 +
                afterRect.top +
                afterRect.height / 2) /
            2;
      } else {
        continue;
      }

      final dx = x - slotX;
      final dy = y - slotY;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  void _commitReorder() {
    final from = _dragFromIndex;
    final insertIndex = _dropInsertIndex;
    if (from == null || insertIndex == null) return;
    if (!_insertWouldChangeOrder(from, insertIndex)) return;
    _moveChipToInsertIndex(from, insertIndex);
  }

  void _onChipDrop(web.Event event) {
    if (_dragFromIndex == null) return;
    if (event is web.DragEvent) {
      event.preventDefault();
      event.stopPropagation();
    }
    _commitReorder();
    _clearDragState();
  }

  void _onChipDragEnd(web.Event event) {
    event.stopPropagation();
    _commitReorder();
    _clearDragState();
  }

  bool _dragStartedOnRemoveButton(web.Event event) {
    final target = event.target;
    if (target is! web.Element) return false;
    return target.closest('.z-tag__remove') != null;
  }

  @override
  Component build(BuildContext context) {
    final chips = _chips;
    final inputId = '${component.id}-add';
    final canReorder = _canReorderChips;

    return div(classes: 'table-edit-chip-input', [
      if (chips.isNotEmpty)
        div(
          classes: [
            'table-edit-chip-input__chips',
            if (_dragFromIndex != null) 'table-edit-chip-input__chips--dragging',
          ].join(' '),
          events: canReorder
              ? {
                  'dragover': _onChipsContainerDragOver,
                  'drop': _onChipDrop,
                }
              : const {},
          [
            for (var i = 0; i < chips.length; i++)
              _ChipItem(
                index: i,
                chip: chips[i],
                canReorder: canReorder,
                isDragging: _dragFromIndex == i,
                showDropPipeLeft: _showsDropPipe(i, _ChipDropSide.left),
                showDropPipeRight: _showsDropPipe(i, _ChipDropSide.right),
                onRemove: component.disabled ? null : () => _removeChip(chips[i]),
                onDragStart: (event) => _onChipDragStart(event, i),
                onDragOver: (event) => _onChipDragOver(event, i),
                onDrop: _onChipDrop,
                onDragEnd: _onChipDragEnd,
              ),
          ],
        ),
      div(classes: 'table-edit-chip-input__add-row', [
        input<String>(
          id: inputId,
          type: .text,
          classes: 'table-edit-chip-input__add-input ${ZonaiClasses.input}',
          attributes: {
            if (component.labelId != null) 'aria-labelledby': component.labelId!,
            'placeholder': component.placeholder,
            'autocomplete': 'off',
          },
          value: _draft,
          disabled: component.disabled,
          onInput: (v) => setState(() => _draft = v),
          events: {
            'keydown': (event) {
              if (event is! web.KeyboardEvent) return;
              if (event.key == 'Enter') {
                event.preventDefault();
                _addChip(_draft);
              }
            },
          },
        ),
        ZonaiButton(
          variant: ZonaiButtonVariant.ghost,
          disabled: component.disabled,
          events: {
            'click': (event) {
              event.preventDefault();
              event.stopPropagation();
              _addChip(_draft);
            },
          },
          child: .text('Add'),
        ),
      ]),
    ]);
  }
}

class _ChipItem extends StatelessComponent {
  const _ChipItem({
    required this.index,
    required this.chip,
    required this.canReorder,
    required this.isDragging,
    required this.showDropPipeLeft,
    required this.showDropPipeRight,
    required this.onRemove,
    required this.onDragStart,
    required this.onDragOver,
    required this.onDrop,
    required this.onDragEnd,
  });

  final int index;
  final String chip;
  final bool canReorder;
  final bool isDragging;
  final bool showDropPipeLeft;
  final bool showDropPipeRight;
  final void Function()? onRemove;
  final void Function(web.Event event) onDragStart;
  final void Function(web.Event event) onDragOver;
  final void Function(web.Event event) onDrop;
  final void Function(web.Event event) onDragEnd;

  @override
  Component build(BuildContext context) {
    return span(
      classes: [
        'table-edit-chip-input__chip-item',
        if (canReorder) 'table-edit-chip-input__chip-item--reorderable',
        if (isDragging) 'table-edit-chip-input__chip-item--dragging',
      ].join(' '),
      attributes: {
        if (canReorder) 'draggable': 'true',
        if (canReorder) 'aria-label': 'Drag to reorder $chip',
      },
      events: {
        if (canReorder) 'dragstart': onDragStart,
        if (canReorder) 'dragend': onDragEnd,
        'dragover': onDragOver,
        'drop': onDrop,
      },
      [
        if (showDropPipeLeft)
          span(
            classes: 'table-edit-chip-input__drop-pipe table-edit-chip-input__drop-pipe--left',
            attributes: {'aria-hidden': 'true'},
            [],
          ),
        ZonaiTag(label: chip, onRemove: onRemove),
        if (showDropPipeRight)
          span(
            classes: 'table-edit-chip-input__drop-pipe table-edit-chip-input__drop-pipe--right',
            attributes: {'aria-hidden': 'true'},
            [],
          ),
      ],
    );
  }
}
