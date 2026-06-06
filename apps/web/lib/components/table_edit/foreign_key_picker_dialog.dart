import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../../constants/button_sizes.dart';
import '../../constants/theme.dart';
import '../../providers/foreign_key_rows_provider.dart';
import '../../providers/table_rows_provider.dart';
import '../../utils/table_cell_edit.dart';
import '../theme/theme_components.dart';
import '../../constants/spacing.dart';

const _searchDebounceDuration = Duration(milliseconds: 300);

/// Whether the FK browse picker overlay is in the document.
bool isForeignKeyPickerOpen() => web.document.querySelector('.fk-picker-backdrop') != null;

/// Modal / bottom sheet to pick one row from a foreign-key target table.
class ForeignKeyPickerDialog extends StatefulComponent {
  const ForeignKeyPickerDialog({
    super.key,
    required this.foreignKey,
    required this.selectedId,
    required this.onSelect,
    required this.onClose,
  });

  final ForeignKeyShape foreignKey;
  final String? selectedId;
  final void Function(String? id, {String? displayLabel}) onSelect;
  final VoidCallback onClose;

  @override
  State<ForeignKeyPickerDialog> createState() => _ForeignKeyPickerDialogState();
}

class _ForeignKeyPickerDialogState extends State<ForeignKeyPickerDialog> {
  var _searchText = '';
  var _appliedSearch = '';
  List<Object?>? _previewRow;
  var _detailOpen = false;
  Timer? _searchDebounce;
  web.EventListener? _documentKeyListener;

  @override
  void initState() {
    super.initState();
    _bindDocumentKeyListener();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _unbindDocumentKeyListener();
    super.dispose();
  }

  void _bindDocumentKeyListener() {
    if (_documentKeyListener != null || !context.binding.isClient) return;
    _documentKeyListener = _onDocumentKeyDown.toJS;
    web.document.addEventListener('keydown', _documentKeyListener);
  }

  void _unbindDocumentKeyListener() {
    final listener = _documentKeyListener;
    if (listener == null) return;
    web.document.removeEventListener('keydown', listener);
    _documentKeyListener = null;
  }

  void _onDocumentKeyDown(web.Event event) {
    if (event is! web.KeyboardEvent) return;
    if (!mounted) return;
    if (event.key != 'Escape') return;

    event.preventDefault();
    event.stopPropagation();

    if (_detailOpen) {
      _closeDetail();
      return;
    }
    component.onClose();
  }

  void _onSearchInput(String value) {
    setState(() => _searchText = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      setState(() => _appliedSearch = _searchText.trim());
    });
  }

  ForeignKeyPickerQuery get _query => ForeignKeyPickerQuery(foreignKey: component.foreignKey, search: _appliedSearch);

  void _openDetail(List<Object?> row) {
    setState(() {
      _previewRow = row;
      _detailOpen = true;
    });
  }

  void _closeDetail() {
    setState(() {
      _detailOpen = false;
    });
  }

  void _confirmSelect(TableRowsData data, List<Object?> row) {
    final value = foreignKeyValueFromRow(data, component.foreignKey, row);
    final label = foreignKeyRowLabel(data, row);
    component.onSelect(value, displayLabel: label.isEmpty ? null : label);
    component.onClose();
  }

  bool _rowIsSelected(TableRowsData data, List<Object?> row) {
    final pkIndex = foreignKeyPrimaryColumnIndex(data, component.foreignKey);
    if (pkIndex == null || component.selectedId == null) return false;
    return '${row[pkIndex]}' == component.selectedId;
  }

  TableRowsData? _loadedRows(AsyncValue<TableRowsData?> asyncRows) {
    return switch (asyncRows) {
      AsyncData(:final value) => value,
      _ => null,
    };
  }

  @override
  Component build(BuildContext context) {
    final asyncRows = context.watch(foreignKeyRowsProvider(_query));
    final loadedData = _loadedRows(asyncRows);
    final showDetail = _detailOpen && _previewRow != null && loadedData != null;

    return div(
      classes: 'fk-picker-backdrop',
      events: {'click': (_) => component.onClose()},
      [
        div(
          classes: 'fk-picker-dialog',
          attributes: {
            'role': 'dialog',
            'aria-modal': 'true',
            'aria-labelledby': showDetail ? 'fk-picker-detail-title' : 'fk-picker-title',
          },
          events: {'click': (event) => event.stopPropagation()},
          [
            if (showDetail)
              _FkPickerDetailView(
                data: loadedData,
                row: _previewRow!,
                onBack: _closeDetail,
                onClose: component.onClose,
                onSelect: () => _confirmSelect(loadedData, _previewRow!),
              )
            else ...[
              div(classes: 'fk-picker-header', [
                h3(id: 'fk-picker-title', classes: 'fk-picker-title', [.text('Select ${component.foreignKey.table}')]),
                button(
                  type: .button,
                  classes: 'fk-picker-close',
                  attributes: {'aria-label': 'Close'},
                  onClick: component.onClose,
                  [_closeIcon()],
                ),
              ]),
              div(classes: 'fk-picker-search-row', [
                input<String>(
                  id: 'fk-picker-search',
                  type: .text,
                  classes: ZonaiClasses.input,
                  attributes: {'placeholder': 'Search rows…', 'autocomplete': 'off'},
                  value: _searchText,
                  onInput: _onSearchInput,
                ),
              ]),
              div(classes: 'fk-picker-body', [
                switch (asyncRows) {
                  AsyncLoading() => p(classes: 'fk-picker-status', [.text('Loading…')]),
                  AsyncError(:final error) => p(classes: 'fk-picker-status fk-picker-status--error', [
                    .text('Failed to load: $error'),
                  ]),
                  AsyncData(:final value) when value == null || value.rows.isEmpty => p(classes: 'fk-picker-status', [
                    .text(_appliedSearch.isEmpty ? 'No rows found.' : 'No matches.'),
                  ]),
                  AsyncData(:final value) => _FkPickerRowList(
                    data: value!,
                    foreignKey: component.foreignKey,
                    selectedId: component.selectedId,
                    isRowSelected: _rowIsSelected,
                    onRowClick: _openDetail,
                  ),
                },
              ]),
              div(classes: 'fk-picker-footer', [
                if (component.selectedId != null)
                  ZonaiButton(
                    variant: ZonaiButtonVariant.ghost,
                    size: ZonaiButtonSize.md,
                    onClick: () {
                      component.onSelect(null);
                      component.onClose();
                    },
                    child: .text('Clear'),
                  ),
                ZonaiButton(variant: ZonaiButtonVariant.secondary, onClick: component.onClose, child: .text('Cancel')),
              ]),
            ],
          ],
        ),
      ],
    );
  }
}

class _FkPickerRowList extends StatelessComponent {
  const _FkPickerRowList({
    required this.data,
    required this.foreignKey,
    required this.selectedId,
    required this.isRowSelected,
    required this.onRowClick,
  });

  final TableRowsData data;
  final ForeignKeyShape foreignKey;
  final String? selectedId;
  final bool Function(TableRowsData data, List<Object?> row) isRowSelected;
  final void Function(List<Object?> row) onRowClick;

  @override
  Component build(BuildContext context) {
    final pkIndex = foreignKeyPrimaryColumnIndex(data, foreignKey);
    if (pkIndex == null) {
      return p(classes: 'fk-picker-status', [.text('Table has no columns.')]);
    }

    final displayColumns = <int>[
      pkIndex,
      for (var i = 0; i < data.columns.length; i++)
        if (i != pkIndex && i < 4) i,
    ];

    return div(classes: 'fk-picker-table-wrap', [
      table(classes: 'fk-picker-table', [
        thead([
          tr([
            for (final i in displayColumns) th([.text(data.columns[i])]),
          ]),
        ]),
        tbody([
          for (final row in data.rows)
            tr(
              classes: ['fk-picker-row', if (isRowSelected(data, row)) 'fk-picker-row--selected'].join(' '),
              events: {'click': (_) => onRowClick(row)},
              [
                for (final i in displayColumns) td([.text(row[i] == null ? '—' : '${row[i]}')]),
              ],
            ),
        ]),
      ]),
    ]);
  }
}

/// Full-dialog row detail (replaces the list until Back).
class _FkPickerDetailView extends StatelessComponent {
  const _FkPickerDetailView({
    required this.data,
    required this.row,
    required this.onBack,
    required this.onClose,
    required this.onSelect,
  });

  final TableRowsData data;
  final List<Object?> row;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final VoidCallback onSelect;

  @override
  Component build(BuildContext context) {
    return div(classes: 'fk-picker-detail-view', [
      div(classes: 'fk-picker-header', [
        h3(id: 'fk-picker-detail-title', classes: 'fk-picker-title', [.text('Row details')]),
        button(
          type: .button,
          classes: 'fk-picker-close',
          attributes: {'aria-label': 'Close'},
          onClick: onClose,
          [_closeIcon()],
        ),
      ]),
      div(classes: 'fk-picker-detail-body', [_FkPickerDetailFields(data: data, row: row)]),
      div(classes: 'fk-picker-detail-footer', [
        ZonaiButton(variant: ZonaiButtonVariant.ghost, size: ZonaiButtonSize.md, onClick: onBack, child: .text('Back')),
        ZonaiButton(variant: ZonaiButtonVariant.primary, onClick: onSelect, child: .text('Select')),
      ]),
    ]);
  }
}

class _FkPickerDetailFields extends StatelessComponent {
  const _FkPickerDetailFields({required this.data, required this.row});

  final TableRowsData data;
  final List<Object?> row;

  @override
  Component build(BuildContext context) {
    return div(classes: 'fk-picker-detail-fields', [
      for (var i = 0; i < data.columns.length; i++)
        if (!data.columnShapes[i].isSecret)
          div(classes: 'fk-picker-detail-field', [
            span(classes: 'fk-picker-detail-label', [.text(columnShapeHeaderLabel(data.columnShapes[i]))]),
            span(classes: 'fk-picker-detail-value', [.text(formatReadOnlyCell(row[i], data.columnShapes[i]))]),
          ]),
    ]);
  }
}

Component _closeIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 16.px,
    height: 16.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M4 4l8 8M12 4 4 12',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
}

@css
List<StyleRule> get foreignKeyPickerDialogStyles => [
  css('.fk-picker-backdrop').styles(
    position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .all(ZonaiSpacing.s11),
    raw: const {'z-index': '1200', 'background': 'rgba(0,0,0,0.4)'},
  ),
  css('.fk-picker-dialog').styles(
    width: 100.percent,
    maxWidth: 640.px,
    maxHeight: 80.vh,
    display: .flex,
    flexDirection: FlexDirection.column,
    backgroundColor: surfaceColor,
    radius: .all(Radius.circular(12.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    overflow: Overflow.hidden,
    raw: const {'box-shadow': 'var(--zonai-shadow)'},
  ),
  css('.fk-picker-header').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .spaceBetween,
    flex: Flex(grow: 0, shrink: 0),
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s8),
    raw: const {'border-bottom': '1px solid var(--zonai-border)'},
  ),
  css('.fk-picker-title').styles(margin: .zero, fontSize: 1.125.rem, fontWeight: .w600),
  css('.fk-picker-close').styles(
    display: .flex,
    padding: .all(ZonaiSpacing.s3),
    border: Border.none,
    backgroundColor: Colors.transparent,
    cursor: .pointer,
    color: mutedColor,
  ),
  css('.fk-picker-search-row').styles(
    flex: Flex(grow: 0, shrink: 0),
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s6),
  ),
  css('.fk-picker-body').styles(
    flex: Flex(grow: 1, shrink: 1),
    overflow: Overflow.auto,
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s4),
    minHeight: 120.px,
  ),
  css('.fk-picker-status').styles(color: mutedColor, fontSize: 0.875.rem),
  css('.fk-picker-status--error').styles(color: errorColor),
  css('.fk-picker-table-wrap').styles(overflow: Overflow.auto, width: 100.percent),
  css('.fk-picker-table').styles(width: 100.percent, fontSize: 0.875.rem, raw: const {'border-collapse': 'collapse'}),
  css('.fk-picker-table th').styles(
    textAlign: TextAlign.left,
    padding: .symmetric(horizontal: ZonaiSpacing.s5, vertical: ZonaiSpacing.s4),
    color: mutedColor,
    fontWeight: .w500,
    raw: const {'border-bottom': '1px solid var(--zonai-border)'},
  ),
  css('.fk-picker-table td').styles(
    padding: .symmetric(horizontal: ZonaiSpacing.s5, vertical: ZonaiSpacing.s4),
    raw: const {'border-bottom': '1px solid var(--zonai-border)'},
  ),
  css('.fk-picker-row').styles(cursor: .pointer),
  css('.fk-picker-row:hover td').styles(backgroundColor: hoverColor),
  css('.fk-picker-row--selected td').styles(backgroundColor: selectedBgColor),
  css('.fk-picker-footer').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    justifyContent: .end,
    gap: Gap.all(ZonaiSpacing.s4),
    flex: Flex(grow: 0, shrink: 0),
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s7),
    raw: const {'border-top': '1px solid var(--zonai-border)'},
  ),
  css(
    '.fk-picker-footer .z-btn--ghost',
  ).styles(fontWeight: .w500, backgroundColor: Colors.transparent, border: Border.none, color: mutedColor),
  css(
    '.fk-picker-footer .z-btn--ghost:hover:not(:disabled)',
  ).styles(backgroundColor: hoverColor, color: fgColor, border: Border.none),
  css('.fk-picker-footer .z-btn + .z-btn').styles(margin: .zero),
  css('.fk-picker-detail-view').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    flex: Flex(grow: 1, shrink: 1),
    minHeight: 0.px,
    height: 100.percent,
  ),
  css('.fk-picker-detail-body').styles(
    flex: Flex(grow: 1, shrink: 1),
    overflow: Overflow.auto,
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s6),
  ),
  css(
    '.fk-picker-detail-fields',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s6)),
  css(
    '.fk-picker-detail-field',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2)),
  css('.fk-picker-detail-label').styles(
    fontSize: 0.75.rem,
    fontWeight: .w500,
    color: mutedColor,
    textTransform: .upperCase,
    letterSpacing: 0.03.rem,
  ),
  css('.fk-picker-detail-value').styles(fontSize: 0.875.rem, raw: const {'word-break': 'break-word'}),
  css('.fk-picker-detail-footer').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    justifyContent: .spaceBetween,
    gap: Gap.all(ZonaiSpacing.s4),
    flex: Flex(grow: 0, shrink: 0),
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s7),
    raw: const {'border-top': '1px solid var(--zonai-border)'},
  ),
  css(
    '.fk-picker-detail-footer .z-btn--ghost',
  ).styles(fontWeight: .w500, backgroundColor: Colors.transparent, border: Border.none, color: mutedColor),
  css(
    '.fk-picker-detail-footer .z-btn--ghost:hover:not(:disabled)',
  ).styles(backgroundColor: hoverColor, color: fgColor, border: Border.none),
  css('.fk-picker-detail-footer .z-btn + .z-btn').styles(margin: .zero),
  css.media(MediaQuery.all(maxWidth: 640.px), [
    css('.fk-picker-backdrop').styles(alignItems: .end, padding: .zero),
    css('.fk-picker-dialog').styles(
      width: .unset,
      maxWidth: .unset,
      maxHeight: 85.vh,
      margin: .symmetric(horizontal: 12.px, vertical: 12.px),
      radius: BorderRadius.only(topLeft: Radius.circular(16.px), topRight: Radius.circular(16.px)),
      transform: Transform.none,
    ),
  ]),
];
