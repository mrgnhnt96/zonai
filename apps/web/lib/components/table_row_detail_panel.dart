import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../constants/theme.dart';
import '../providers/app_tooltip_provider.dart';
import '../providers/session_user_provider.dart';
import '../providers/table_row_detail_provider.dart';
import '../providers/table_rows_provider.dart';
import '../providers/toast_provider.dart';
import '../utils/dom_event_values.dart';
import '../utils/table_cell_edit.dart';
import '../utils/table_row_edit.dart';
import '../utils/user_facing_error.dart';
import '../utils/table_rows_json.dart';
import 'app_tooltip_overlay.dart';

const _collapsibleMinLength = 320;
const _slideDuration = Duration(milliseconds: 250);
const _panelMinWidthPx = 380.0;
const _panelMaxWidthFraction = 3 / 4;
const _resizeStripWidthPx = 20.0;
const _footerHorizontalPaddingPx = 16.0;
const _footerActionsGapPx = 8.0;
const _footerContentMaxWidthPx =
    _panelMinWidthPx - _resizeStripWidthPx - _footerHorizontalPaddingPx * 2;
const _footerSaveBtnMaxWidthPx = (_footerContentMaxWidthPx - _footerActionsGapPx) * 3 / 4;
const _footerCancelBtnMaxWidthPx = (_footerContentMaxWidthPx - _footerActionsGapPx) * 1 / 4;

class TableRowDetailPanel extends StatefulComponent {
  const TableRowDetailPanel({super.key});

  @override
  State<TableRowDetailPanel> createState() => _TableRowDetailPanelState();
}

class _TableRowDetailPanelState extends State<TableRowDetailPanel> {
  var _render = false;
  var _open = false;
  var _panelWidthPx = _panelMinWidthPx;
  var _resizing = false;
  bool? _lastHadDetail;
  TableRowDetailState? _cachedDetail;
  Timer? _unmountTimer;
  Timer? _openTimer;
  web.EventListener? _documentKeyListener;
  web.EventListener? _documentResizeMoveListener;
  web.EventListener? _documentResizeUpListener;
  web.EventListener? _handleResizeDownListener;
  web.Element? _resizeBoundPanel;
  var _resizeBindAttempts = 0;
  Timer? _resizeBindTimer;
  var _resizeListenersActive = false;
  var _showRawJson = false;
  String? _rawJsonRowKey;
  var _editing = false;
  var _saving = false;
  List<Object?>? _draft;
  Map<int, String> _textInputs = {};
  _PendingDismiss? _pendingDismiss;

  @override
  void initState() {
    super.initState();
    _documentResizeMoveListener = _onDocumentResizeMove.toJS;
    _documentResizeUpListener = _onDocumentResizeUp.toJS;
    _handleResizeDownListener = _onResizeHandleMouseDown.toJS;
  }

  double _viewportWidthPx() {
    final visualViewport = web.window.visualViewport;
    if (visualViewport != null) {
      final width = jsNumProperty(visualViewport, 'width');
      if (width > 0) return width;
    }
    final innerWidth = jsNumProperty(web.window, 'innerWidth');
    if (innerWidth > 0) return innerWidth;
    final doc = web.document.documentElement;
    if (doc != null) {
      final clientWidth = jsNumProperty(doc, 'clientWidth');
      if (clientWidth > 0) return clientWidth;
    }
    return 1200;
  }

  double get _panelMaxWidthPx {
    final vw = _viewportWidthPx();
    return math.max(_panelMinWidthPx, vw * _panelMaxWidthFraction);
  }

  double _panelRightEdgePx() {
    final panel = _resizeBoundPanel;
    if (panel != null) {
      final rect = panel.getBoundingClientRect();
      if (rect.right > 0) return rect.right.toDouble();
    }
    return _viewportWidthPx();
  }

  @override
  void dispose() {
    _unmountTimer?.cancel();
    _openTimer?.cancel();
    _unbindDocumentKeyListener();
    _resizeBindTimer?.cancel();
    _unbindResizeHandleDom();
    _endResizeDrag();
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
    if (!mounted || !_open) return;

    if (event.key == 'Escape') {
      event.preventDefault();
      if (_pendingDismiss != null) {
        setState(() => _pendingDismiss = null);
        return;
      }
      final detail = _cachedDetail;
      if (detail == null) {
        context.read(tableRowDetailProvider.notifier).close();
        return;
      }
      if (_editing) {
        if (detail.openedViaEditShortcut) {
          _requestDismiss(detail, _PendingDismiss.closePanel);
        } else {
          _requestDismiss(detail, _PendingDismiss.cancelEditing);
        }
        return;
      }
      _requestDismiss(detail, _PendingDismiss.closePanel);
      return;
    }

    if (event.key == 'Enter' && (event.metaKey || event.ctrlKey)) {
      if (_pendingDismiss != null || !_editing || _saving) return;
      final detail = _cachedDetail;
      if (detail == null || !_hasUnsavedChanges(detail)) return;
      event.preventDefault();
      _saveRow(detail);
    }
  }

  double? _eventClientX(web.Event event) {
    // Read via JS property — browser may return fractional doubles but the
    // MouseEvent.clientX getter is typed as int and throws on subpixel values.
    return eventClientX(event);
  }

  void _applyPanelWidthPx(double widthPx) {
    final maxWidth = _panelMaxWidthPx;
    final width = widthPx.clamp(_panelMinWidthPx, maxWidth);
    _panelWidthPx = width;
    final panel = _resizeBoundPanel;
    if (panel case web.HTMLElement(:final style)) {
      final widthPxRounded = width.round();
      final maxPxRounded = maxWidth.round();
      style.setProperty('width', '${widthPxRounded}px');
      style.setProperty('max-width', '${maxPxRounded}px');
      style.setProperty('min-width', '${_panelMinWidthPx.round()}px');
    }
  }

  void _applyResizeFromClientX(double clientX) {
    _applyPanelWidthPx(_panelRightEdgePx() - clientX);
  }

  void _onResizeHandleMouseDown(web.Event event) {
    if (!mounted || !context.binding.isClient || _resizeListenersActive) return;
    final clientX = _eventClientX(event);
    if (clientX == null) return;
    event.preventDefault();
    event.stopPropagation();
    _resizeBoundPanel ??= web.document.querySelector('.table-row-detail-panel');
    if (_resizeBoundPanel == null) return;
    _beginResizeDrag(clientX);
  }

  void _beginResizeDrag(double clientX) {
    if (_resizeListenersActive) return;
    _resizing = true;
    _applyResizeFromClientX(clientX);
    _setDocumentResizeCursor(active: true);

    final move = _documentResizeMoveListener;
    final up = _documentResizeUpListener;
    if (move == null || up == null) return;

    _resizeListenersActive = true;
    web.document.addEventListener('mousemove', move);
    web.document.addEventListener('mouseup', up);
    web.document.addEventListener('pointermove', move);
    web.document.addEventListener('pointerup', up);
    web.document.addEventListener('pointercancel', up);
  }

  void _onDocumentResizeMove(web.Event event) {
    if (!mounted || !_resizeListenersActive) return;
    final clientX = _eventClientX(event);
    if (clientX == null) return;
    _applyResizeFromClientX(clientX);
  }

  void _onDocumentResizeUp(web.Event event) {
    if (!mounted) return;
    _endResizeDrag();
    setState(() => _resizing = false);
  }

  void _setDocumentResizeCursor({required bool active}) {
    final body = web.document.body;
    if (body == null) return;
    if (active) {
      body.style.cursor = 'ew-resize';
      body.style.setProperty('user-select', 'none');
    } else {
      body.style.cursor = '';
      body.style.removeProperty('user-select');
    }
  }

  void _endResizeDrag() {
    _setDocumentResizeCursor(active: false);
    if (!_resizeListenersActive) return;
    final move = _documentResizeMoveListener;
    final up = _documentResizeUpListener;
    if (move != null) {
      web.document.removeEventListener('mousemove', move);
      web.document.removeEventListener('pointermove', move);
    }
    if (up != null) {
      web.document.removeEventListener('mouseup', up);
      web.document.removeEventListener('pointerup', up);
      web.document.removeEventListener('pointercancel', up);
    }
    _resizeListenersActive = false;
  }

  void _focusPanel() {
    if (!context.binding.isClient || !mounted) return;
    final el = web.document.querySelector('.table-row-detail-panel');
    if (el is web.HTMLElement) {
      el.focus();
    }
  }

  void _scheduleResizeBind() {
    if (!context.binding.isClient) return;
    _resizeBindTimer?.cancel();
    _resizeBindAttempts = 0;
    void attempt() {
      if (!mounted || !_open) return;
      _resizeBindAttempts++;
      if (_bindResizeHandleDom() || _resizeBindAttempts >= 12) return;
      _resizeBindTimer = Timer(const Duration(milliseconds: 50), attempt);
    }

    scheduleMicrotask(attempt);
  }

  bool _bindResizeHandleDom() {
    if (!context.binding.isClient) return false;
    _unbindResizeHandleDom();
    final panel = web.document.querySelector('.table-row-detail-panel.table-row-detail--open');
    if (panel is! web.HTMLElement) return false;
    _resizeBoundPanel = panel;
    _applyPanelWidthPx(_panelWidthPx);

    final handle = panel.querySelector('.table-row-detail-resize-handle');
    final down = _handleResizeDownListener;
    if (handle is web.HTMLElement && down != null) {
      handle.addEventListener('mousedown', down);
      handle.addEventListener('pointerdown', down);
    }
    return true;
  }

  void _unbindResizeHandleDom() {
    final panel = _resizeBoundPanel;
    final down = _handleResizeDownListener;
    final handle = panel?.querySelector('.table-row-detail-resize-handle');
    if (handle is web.HTMLElement && down != null) {
      handle.removeEventListener('mousedown', down);
      handle.removeEventListener('pointerdown', down);
    }
    _resizeBoundPanel = null;
  }

  void _onOpen() {
    _unmountTimer?.cancel();
    _openTimer?.cancel();
    setState(() {
      _render = true;
      _open = false;
    });
    _openTimer = Timer(const Duration(milliseconds: 20), () {
      if (!mounted) return;
      setState(() => _open = true);
      _bindDocumentKeyListener();
      scheduleMicrotask(() {
        if (!mounted || !_open) return;
        _focusPanel();
        _scheduleResizeBind();
      });
    });
  }

  void _onClose() {
    if (!_render) return;
    _openTimer?.cancel();
    _resizeBindTimer?.cancel();
    if (context.binding.isClient) {
      context.read(appTooltipProvider.notifier).hide();
    }
    _unbindDocumentKeyListener();
    _unbindResizeHandleDom();
    _endResizeDrag();
    setState(() {
      _open = false;
      _resizing = false;
      _saving = false;
      _pendingDismiss = null;
    });
    _unmountTimer?.cancel();
    _unmountTimer = Timer(_slideDuration, () {
      if (!mounted) return;
      setState(() {
        _render = false;
        _cachedDetail = null;
        _showRawJson = false;
        _rawJsonRowKey = null;
        _editing = false;
        _draft = null;
        _textInputs = {};
      });
    });
  }

  void _syncDetail(TableRowDetailState? detail) {
    final hasDetail = detail != null;
    if (hasDetail) {
      final prev = _cachedDetail;
      final rowChanged = prev?.rowKey != detail.rowKey;
      final viewChanged = prev?.viewMode != detail.viewMode;
      if (rowChanged) {
        _editing = false;
        _saving = false;
        _draft = null;
        _textInputs = {};
        _showRawJson = false;
        _rawJsonRowKey = null;
      }
      _cachedDetail = detail;
      if (rowChanged || viewChanged) {
        scheduleMicrotask(() {
          if (!mounted) return;
          final current = context.read(tableRowDetailProvider);
          if (current == null || current.rowKey != detail.rowKey) return;
          _applyViewModeFromDetail(current);
        });
      }
    }

    if (_lastHadDetail == hasDetail) {
      return;
    }

    if (hasDetail) {
      if (!_render) {
        scheduleMicrotask(_onOpen);
      } else if (!_open) {
        // Re-open while a close animation was still running.
        _unmountTimer?.cancel();
        _openTimer?.cancel();
        scheduleMicrotask(_onOpen);
      }
    } else if (_lastHadDetail == true) {
      scheduleMicrotask(_onClose);
    }

    _lastHadDetail = hasDetail;
  }

  bool _canEditRow(TableRowDetailState detail) {
    return canEditTableRows(
      sqliteName: detail.sqliteName,
      columns: detail.columns,
      columnShapes: detail.columnShapes,
      row: detail.row,
    );
  }

  void _startEditing(TableRowDetailState detail) {
    setState(() {
      _editing = true;
      _draft = List<Object?>.from(detail.row);
      _textInputs = {
        for (var i = 0; i < detail.row.length; i++)
          if (_usesTextInput(detail.columnShapes.elementAtOrNull(i)))
            i: cellToEditString(detail.row[i], detail.columnShapes.elementAtOrNull(i)),
      };
      _showRawJson = false;
      _rawJsonRowKey = null;
    });
  }

  void _applyViewModeFromDetail(TableRowDetailState detail) {
    switch (detail.viewMode) {
      case TableRowDetailViewMode.fields:
        if (!_editing && !_showRawJson) return;
        setState(() {
          _editing = false;
          _draft = null;
          _textInputs = {};
          _pendingDismiss = null;
          _showRawJson = false;
          _rawJsonRowKey = null;
        });
      case TableRowDetailViewMode.json:
        if (_showRawJson && _rawJsonRowKey == detail.rowKey && !_editing) return;
        setState(() {
          _editing = false;
          _draft = null;
          _textInputs = {};
          _pendingDismiss = null;
          _showRawJson = true;
          _rawJsonRowKey = detail.rowKey;
        });
      case TableRowDetailViewMode.edit:
        if (!_canEditRow(detail)) {
          context.read(tableRowDetailProvider.notifier).setViewMode(TableRowDetailViewMode.fields);
          return;
        }
        if (_editing) return;
        _startEditing(detail);
    }
  }

  void _cancelEditing() {
    context.read(tableRowDetailProvider.notifier).setViewMode(TableRowDetailViewMode.fields);
    setState(() {
      _editing = false;
      _draft = null;
      _textInputs = {};
      _pendingDismiss = null;
    });
  }

  bool _hasUnsavedChanges(TableRowDetailState detail) {
    if (!_editing || _draft == null) return false;

    try {
      return diffRowUpdates(
        original: detail.row,
        draft: _parsedDraft(detail),
        columns: detail.columns,
        columnShapes: detail.columnShapes,
      ).isNotEmpty;
    } on FormatException {
      for (var i = 0; i < detail.row.length; i++) {
        final shape = detail.columnShapes.elementAtOrNull(i);
        if (shape == null || !isColumnEditable(shape)) continue;
        if (shape.kind == ColumnShapeKind.boolean || shape.kind == ColumnShapeKind.isVerified) {
          if (!cellValuesEqual(detail.row[i], _draft![i], shape)) return true;
        } else {
          final text = _textInputs[i];
          if (text != null && text != cellToEditString(detail.row[i], shape)) return true;
        }
      }
      return false;
    }
  }

  void _requestDismiss(TableRowDetailState detail, _PendingDismiss action) {
    if (_saving) return;
    if (_hasUnsavedChanges(detail)) {
      setState(() => _pendingDismiss = action);
      return;
    }
    _executeDismiss(action);
  }

  void _executeDismiss(_PendingDismiss action) {
    switch (action) {
      case _PendingDismiss.closePanel:
        context.read(tableRowDetailProvider.notifier).close();
      case _PendingDismiss.cancelEditing:
        _cancelEditing();
    }
  }

  bool _usesTextInput(ColumnShape? shape) {
    if (shape == null || !isColumnEditable(shape)) return false;
    return switch (shape.kind) {
      ColumnShapeKind.boolean || ColumnShapeKind.isVerified => false,
      _ => true,
    };
  }

  List<Object?> _parsedDraft(TableRowDetailState detail) {
    final draft = _draft;
    if (draft == null) return detail.row;

    final parsed = List<Object?>.from(draft);
    for (var i = 0; i < detail.row.length; i++) {
      final shape = detail.columnShapes.elementAtOrNull(i);
      if (shape == null || !isColumnEditable(shape)) {
        parsed[i] = detail.row[i];
        continue;
      }
      if (shape.kind == ColumnShapeKind.boolean || shape.kind == ColumnShapeKind.isVerified) {
        continue;
      }
      final text = _textInputs[i];
      if (text == null) continue;
      parsed[i] = parseEditValue(
        draftValue: detail.row[i],
        textInput: text,
        shape: shape,
      );
    }
    return parsed;
  }

  Component _buildDetailField(BuildContext context, TableRowDetailState detail, int index) {
    final shape =
        detail.columnShapes.elementAtOrNull(index) ??
        ColumnShape(
          name: detail.columns.elementAtOrNull(index) ?? 'column_$index',
          kind: ColumnShapeKind.text,
          isNullable: true,
          isPrimaryKey: false,
          autoIncrement: false,
          sqlType: 'TEXT',
        );
    final label = columnShapeHeaderLabel(shape);

    if (_editing && isColumnEditable(shape)) {
      return _EditDetailField(
        fieldLabel: label,
        shape: shape,
        value: _draft?[index],
        textValue: _textInputs[index] ?? '',
        disabled: _saving,
        onBoolChanged: (value) {
          setState(() {
            _draft ??= List<Object?>.from(detail.row);
            _draft![index] = value;
          });
        },
        onTextChanged: (value) {
          setState(() => _textInputs = {..._textInputs, index: value});
        },
      );
    }

    return _DetailField(
      label: label,
      value: formatReadOnlyCell(detail.row[index], shape),
      shape: shape,
      readOnlyHint: _editing && !isColumnEditable(shape),
    );
  }

  Future<void> _saveRow(TableRowDetailState detail) async {
    if (_saving) return;

    List<Object?> parsedDraft;
    try {
      parsedDraft = _parsedDraft(detail);
    } on FormatException catch (e) {
      context.read(toastProvider.notifier).showError(userFacingError(e));
      return;
    }

    final updates = diffRowUpdates(
      original: detail.row,
      draft: parsedDraft,
      columns: detail.columns,
      columnShapes: detail.columnShapes,
    );

    if (updates.isEmpty) {
      _cancelEditing();
      return;
    }

    setState(() => _saving = true);
    try {
      final record = await context.read(tableRowsProvider.notifier).updateRow(
        sqliteName: detail.sqliteName,
        row: detail.row,
        columns: detail.columns,
        columnShapes: detail.columnShapes,
        changedFields: updates,
      );
      if (!mounted) return;

      final newRow = rowFromRecord(record, detail.columns);
      final detailNotifier = context.read(tableRowDetailProvider.notifier);
      detailNotifier.replaceRow(newRow);
      detailNotifier.setViewMode(TableRowDetailViewMode.fields);
      context.read(toastProvider.notifier).showSuccess('Row updated');
      setState(() {
        _editing = false;
        _saving = false;
        _draft = null;
        _textInputs = {};
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.read(toastProvider.notifier).showError(userFacingError(e));
    }
  }

  @override
  Component build(BuildContext context) {
    if (!context.binding.isClient) {
      return Component.empty();
    }

    final detail = context.watch(tableRowDetailProvider);
    _syncDetail(detail);

    if (!_render || _cachedDetail == null) {
      return Component.empty();
    }

    final cached = _cachedDetail!;
    final sessionUser = context.watch(sessionUserProvider);
    final canEditRows = sessionUser?.canEdit == true;
    final rowEditable = canEditRows && _canEditRow(cached);
    final hasUnsavedChanges = _hasUnsavedChanges(cached);
    void close() => _requestDismiss(cached, _PendingDismiss.closePanel);
    final subtitle = _detailSubtitle(cached);
    final showRawJson = !_editing && _showRawJson && _rawJsonRowKey == cached.rowKey;
    final openClass = _open ? ' table-row-detail--open' : '';
    final editingClass = _editing ? ' table-row-detail--editing' : '';
    final resizeClass = _resizing ? ' table-row-detail--resizing' : '';
    final maxWidth = _panelMaxWidthPx.round();
    final panelStyle =
        'width: ${_panelWidthPx.round()}px; min-width: ${_panelMinWidthPx.round()}px; max-width: ${maxWidth}px;';

    return Component.fragment([
      div(
        classes: 'table-row-detail-backdrop$openClass',
        attributes: {'aria-hidden': 'true'},
        events: {'click': (_) => close()},
        [],
      ),
      aside(
        classes: 'table-row-detail-panel$openClass$resizeClass$editingClass',
        attributes: {'aria-label': 'Row details', 'tabindex': '-1', 'style': panelStyle},
        events: {'click': (event) => event.stopPropagation()},
        [
          div(
            classes: 'table-row-detail-resize-handle',
            attributes: {
              'aria-hidden': 'true',
              'style':
                  'position: absolute; top: 0; left: 0; bottom: 0; height: 100%; '
                  'width: ${_resizeStripWidthPx.round()}px; cursor: ew-resize; touch-action: none; '
                  'background: transparent; z-index: 10;',
            },
            events: {
              'mousedown': _onResizeHandleMouseDown,
              'pointerdown': _onResizeHandleMouseDown,
              ...appTooltipEvents(context, text: 'Drag to resize'),
            },
            [],
          ),
          div(classes: 'table-row-detail-main', [
            div(classes: 'table-row-detail-header', [
              div(classes: 'table-row-detail-header-text', [
                h2(classes: 'table-row-detail-title', [.text('Row details')]),
                if (subtitle.isNotEmpty) p(classes: 'table-row-detail-subtitle', [.text(subtitle)]),
              ]),
              div(classes: 'table-row-detail-header-actions', [
                if (!_editing)
                  button(
                    classes: 'table-row-detail-view-toggle',
                    type: .button,
                    attributes: {
                      'aria-label': showRawJson ? 'Show field details' : 'Show raw JSON',
                    },
                    onClick: () {
                      context.read(appTooltipProvider.notifier).hide();
                      final notifier = context.read(tableRowDetailProvider.notifier);
                      notifier.setViewMode(
                        showRawJson ? TableRowDetailViewMode.fields : TableRowDetailViewMode.json,
                      );
                    },
                    [.text(showRawJson ? 'Fields' : 'JSON')],
                  ),
                button(
                  classes: 'table-row-detail-close',
                  type: .button,
                  attributes: {'aria-label': 'Close row details'},
                  onClick: close,
                  [.text('×')],
                ),
              ]),
            ]),
            div(classes: 'table-row-detail-body', [
              if (showRawJson)
                _RawJsonCard(json: _detailRawJson(cached))
              else
                for (var i = 0; i < cached.row.length; i++)
                  _buildDetailField(context, cached, i),
            ]),
            if (rowEditable && !showRawJson)
              div(classes: 'table-row-detail-footer', [
                if (_editing)
                  div(classes: 'table-row-detail-footer-actions', [
                    button(
                      classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--primary',
                      type: .button,
                      attributes: {
                        'aria-label': 'Save row',
                        if (_saving || !hasUnsavedChanges) 'disabled': 'true',
                      },
                      onClick: (_saving || !hasUnsavedChanges) ? null : () => _saveRow(cached),
                      [.text(_saving ? 'Saving…' : 'Save')],
                    ),
                    button(
                      classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--cancel',
                      type: .button,
                      attributes: {
                        'aria-label': 'Cancel editing',
                        if (_saving) 'disabled': 'true',
                      },
                      onClick: _saving ? null : () => _requestDismiss(cached, _PendingDismiss.cancelEditing),
                      [.text('Cancel')],
                    ),
                  ])
                else
                  button(
                    classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--primary',
                    type: .button,
                    attributes: {'aria-label': 'Edit row'},
                    onClick: () => context.read(tableRowDetailProvider.notifier).setViewMode(
                      TableRowDetailViewMode.edit,
                    ),
                    [.text('Edit row')],
                  ),
              ]),
          ]),
        ],
      ),
      if (_pendingDismiss != null) _DiscardChangesDialog(
        onKeepEditing: () => setState(() => _pendingDismiss = null),
        onDiscard: () {
          final action = _pendingDismiss!;
          setState(() => _pendingDismiss = null);
          _executeDismiss(action);
        },
      ),
    ]);
  }
}

enum _PendingDismiss { closePanel, cancelEditing }

class _DiscardChangesDialog extends StatelessComponent {
  const _DiscardChangesDialog({
    required this.onKeepEditing,
    required this.onDiscard,
  });

  final VoidCallback onKeepEditing;
  final VoidCallback onDiscard;

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'table-row-detail-discard-backdrop',
      events: {'click': (_) => onKeepEditing()},
      [
        div(
          classes: 'table-row-detail-discard-dialog',
          attributes: {
            'role': 'dialog',
            'aria-modal': 'true',
            'aria-labelledby': 'table-row-detail-discard-title',
          },
          events: {'click': (event) => event.stopPropagation()},
          [
            h3(
              id: 'table-row-detail-discard-title',
              classes: 'table-row-detail-discard-title',
              [.text('Discard changes?')],
            ),
            p(classes: 'table-row-detail-discard-message', [
              .text('You have unsaved changes. If you leave now, your edits will be lost.'),
            ]),
            div(classes: 'table-row-detail-discard-actions', [
              button(
                classes: 'table-row-detail-discard-btn table-row-detail-discard-btn--secondary',
                type: .button,
                onClick: onKeepEditing,
                [.text('Keep editing')],
              ),
              button(
                classes: 'table-row-detail-discard-btn table-row-detail-discard-btn--danger',
                type: .button,
                onClick: onDiscard,
                [.text('Discard')],
              ),
            ]),
          ],
        ),
      ],
    );
  }
}

String _detailRawJson(TableRowDetailState detail) {
  final map = tableRowToJsonMap(columns: detail.columns, row: detail.row);
  const encoder = JsonEncoder.withIndent('  ');
  try {
    return encoder.convert(map);
  } on Object {
    return encoder.convert({
      for (final entry in map.entries) entry.key: entry.value?.toString(),
    });
  }
}

class _RawJsonCard extends StatelessComponent {
  const _RawJsonCard({required this.json});

  final String json;

  @override
  Component build(BuildContext context) {
    return div(classes: 'table-row-detail-json-card', [
      div(classes: 'table-row-detail-json-card-toolbar', [
        _CopyFieldValueButton(label: 'JSON', text: json),
      ]),
      pre(classes: 'table-row-detail-json-card-pre', [
        code(classes: 'table-row-detail-json-highlight', _highlightedJsonSpans(json)),
      ]),
    ]);
  }
}

enum _JsonHighlightKind { key, string, number, boolean, nullToken, punctuation, whitespace }

final class _JsonHighlightToken {
  const _JsonHighlightToken(this.text, this.kind);

  final String text;
  final _JsonHighlightKind kind;
}

List<Component> _highlightedJsonSpans(String source) {
  return [
    for (final token in _tokenizeJson(source))
      span(classes: _jsonHighlightClass(token.kind), [.text(token.text)]),
  ];
}

String _jsonHighlightClass(_JsonHighlightKind kind) => switch (kind) {
  _JsonHighlightKind.key => 'json-hl-key',
  _JsonHighlightKind.string => 'json-hl-string',
  _JsonHighlightKind.number => 'json-hl-number',
  _JsonHighlightKind.boolean => 'json-hl-bool',
  _JsonHighlightKind.nullToken => 'json-hl-null',
  _JsonHighlightKind.punctuation => 'json-hl-punct',
  _JsonHighlightKind.whitespace => 'json-hl-ws',
};

List<_JsonHighlightToken> _tokenizeJson(String source) {
  final tokens = <_JsonHighlightToken>[];
  var i = 0;

  while (i < source.length) {
    final char = source[i];

    if (char == '"') {
      final start = i;
      i++;
      while (i < source.length) {
        if (source[i] == r'\') {
          i += 2;
          continue;
        }
        if (source[i] == '"') {
          i++;
          break;
        }
        i++;
      }
      final text = source.substring(start, i);
      var peek = i;
      while (peek < source.length && _isJsonWhitespace(source[peek])) {
        peek++;
      }
      final kind = peek < source.length && source[peek] == ':'
          ? _JsonHighlightKind.key
          : _JsonHighlightKind.string;
      tokens.add(_JsonHighlightToken(text, kind));
      continue;
    }

    if (char == '{' || char == '}' || char == '[' || char == ']' || char == ':' || char == ',') {
      tokens.add(_JsonHighlightToken(char, _JsonHighlightKind.punctuation));
      i++;
      continue;
    }

    if (_isJsonWhitespace(char)) {
      final start = i;
      while (i < source.length && _isJsonWhitespace(source[i])) {
        i++;
      }
      tokens.add(_JsonHighlightToken(source.substring(start, i), _JsonHighlightKind.whitespace));
      continue;
    }

    if (char == '-' || _isJsonDigit(char)) {
      final start = i;
      if (source[i] == '-') i++;
      while (i < source.length) {
        final c = source[i];
        if (_isJsonDigit(c) || c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') {
          i++;
          continue;
        }
        break;
      }
      tokens.add(_JsonHighlightToken(source.substring(start, i), _JsonHighlightKind.number));
      continue;
    }

    if (source.startsWith('true', i)) {
      tokens.add(const _JsonHighlightToken('true', _JsonHighlightKind.boolean));
      i += 4;
      continue;
    }
    if (source.startsWith('false', i)) {
      tokens.add(const _JsonHighlightToken('false', _JsonHighlightKind.boolean));
      i += 5;
      continue;
    }
    if (source.startsWith('null', i)) {
      tokens.add(const _JsonHighlightToken('null', _JsonHighlightKind.nullToken));
      i += 4;
      continue;
    }

    tokens.add(_JsonHighlightToken(char, _JsonHighlightKind.punctuation));
    i++;
  }

  return tokens;
}

bool _isJsonWhitespace(String char) => char == ' ' || char == '\t' || char == '\n' || char == '\r';

bool _isJsonDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

String _detailSubtitle(TableRowDetailState detail) {
  final pkShapes = detail.columnShapes.where((shape) => shape.isPrimaryKey).toList();
  if (pkShapes.isEmpty) return '';

  final parts = <String>[];
  for (final shape in pkShapes) {
    final index = detail.columns.indexOf(shape.name);
    if (index < 0) continue;
    parts.add('${shape.name}=${formatSchemaCell(detail.row[index], shape, truncate: false)}');
  }
  return parts.join(' · ');
}

class _DetailField extends StatelessComponent {
  const _DetailField({
    required this.label,
    required this.value,
    required this.shape,
    this.readOnlyHint = false,
  });

  final String label;
  final String value;
  final ColumnShape? shape;
  final bool readOnlyHint;

  @override
  Component build(BuildContext context) {
    const readOnlyTooltip = 'Read-only';
    final fieldClass = readOnlyHint
        ? 'table-row-detail-field table-row-detail-field--readonly-in-edit'
        : 'table-row-detail-field';

    return div(
      classes: fieldClass,
      events: readOnlyHint
          ? appTooltipEvents(
              context,
              text: readOnlyTooltip,
              placement: AppTooltipPlacement.belowLeft,
            )
          : const {},
      [
        div(classes: 'table-row-detail-label-row', [
            span(classes: 'table-row-detail-label table-row-detail-label--stacked', [.text(label)]),
            if (!readOnlyHint) _CopyFieldValueButton(label: label, text: value),
          ],
        ),
        _DetailFieldValue(value: value, shape: shape),
      ],
    );
  }
}

class _EditDetailField extends StatelessComponent {
  const _EditDetailField({
    required this.fieldLabel,
    required this.shape,
    required this.value,
    required this.textValue,
    required this.disabled,
    required this.onBoolChanged,
    required this.onTextChanged,
  });

  final String fieldLabel;
  final ColumnShape shape;
  final Object? value;
  final String textValue;
  final bool disabled;
  final void Function(bool value) onBoolChanged;
  final void Function(String value) onTextChanged;

  @override
  Component build(BuildContext context) {
    final fieldId = 'table-row-edit-${shape.name}';

    final enumHint = shape.kind == ColumnShapeKind.enum_ && shape.enumValues.isNotEmpty
        ? shape.enumValues.join(', ')
        : null;

    return div(classes: 'table-row-detail-field table-row-detail-field--edit', [
      label(
        htmlFor: fieldId,
        classes: 'table-row-detail-label table-row-detail-label--stacked',
        [.text(fieldLabel)],
      ),
      switch (shape.kind) {
        ColumnShapeKind.boolean || ColumnShapeKind.isVerified => input<bool>(
          id: fieldId,
          type: InputType.checkbox,
          classes: 'table-row-detail-edit-checkbox',
          checked: cellEditValueAsBool(value),
          disabled: disabled,
          onChange: onBoolChanged,
        ),
        ColumnShapeKind.enum_ => input<String>(
          id: fieldId,
          type: InputType.text,
          classes: 'table-row-detail-edit-input',
          value: textValue,
          disabled: disabled,
          attributes: {
            if (enumHint != null) 'placeholder': enumHint,
            if (shape.isNullable) 'aria-description': 'Leave empty for null',
          },
          onInput: onTextChanged,
        ),
        _ => input<String>(
          id: fieldId,
          type: InputType.text,
          classes: 'table-row-detail-edit-input',
          value: textValue,
          disabled: disabled,
          attributes: {
            if (shape.isNullable) 'placeholder': 'Leave empty for null',
          },
          onInput: onTextChanged,
        ),
      },
    ]);
  }
}

class _CopyFieldValueButton extends StatefulComponent {
  const _CopyFieldValueButton({required this.label, required this.text});

  final String label;
  final String text;

  @override
  State<_CopyFieldValueButton> createState() => _CopyFieldValueButtonState();
}

class _CopyFieldValueButtonState extends State<_CopyFieldValueButton> {
  var _copied = false;
  AppTooltipPlacement _tooltipPlacement = AppTooltipPlacement.belowCenter;
  double? _tooltipTop;
  double? _tooltipLeft;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  String get _tooltipText => _copied ? 'Copied' : 'Copy ${component.label}';

  void _showTooltip(web.Event event) {
    if (!context.binding.isClient) return;
    final el = event.currentTarget;
    if (el is! web.HTMLElement) return;
    final rect = el.getBoundingClientRect();
    _tooltipTop = rect.bottom + 6;
    _tooltipLeft = rect.left + rect.width / 2;
    _tooltipPlacement = AppTooltipPlacement.belowCenter;
    context.read(appTooltipProvider.notifier).show(
      text: _tooltipText,
      top: _tooltipTop!,
      left: _tooltipLeft!,
      placement: _tooltipPlacement,
    );
  }

  void _hideTooltip(_) {
    context.read(appTooltipProvider.notifier).hide();
  }

  void _onKeyDown(web.Event event) {
    if (event is! web.KeyboardEvent) return;
    if (event.key != 'Enter' && event.key != ' ') return;
    event.preventDefault();
    _onCopy();
  }

  void _onCopy() {
    if (!context.binding.isClient) return;
    web.window.navigator.clipboard.writeText(component.text).toDart.ignore();
    _resetTimer?.cancel();
    setState(() => _copied = true);
    final top = _tooltipTop;
    final left = _tooltipLeft;
    if (top != null && left != null) {
      context.read(appTooltipProvider.notifier).show(
        text: _tooltipText,
        top: top,
        left: left,
        placement: _tooltipPlacement,
      );
    }
    _resetTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  Component build(BuildContext context) {
    return span(
      classes: 'table-row-detail-copy-wrap',
      attributes: {
        'role': 'button',
        'tabindex': '0',
        'aria-label': _tooltipText,
      },
      events: {
        'click': (_) => _onCopy(),
        'keydown': _onKeyDown,
        'mouseenter': _showTooltip,
        'mouseleave': _hideTooltip,
        'focus': _showTooltip,
        'blur': _hideTooltip,
      },
      [
        span(
          classes: 'table-row-detail-copy${_copied ? ' table-row-detail-copy--copied' : ''}',
          [_copied ? _checkIconSvg() : _copyIconSvg()],
        ),
      ],
    );
  }
}

Component _copyIconSvg() {
  return svg(
    viewBox: '0 0 16 16',
    width: 11.px,
    height: 11.px,
    classes: 'table-row-detail-copy-icon',
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.25',
        d: 'M5.5 3.5h6a1 1 0 0 1 1 1v6.5',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
      rect(
        attributes: const {
          'x': '3.5',
          'y': '5.5',
          'width': '8',
          'height': '8',
          'rx': '1',
          'stroke': 'currentColor',
          'stroke-width': '1.25',
          'fill': 'none',
        },
        [],
      ),
    ],
  );
}

Component _checkIconSvg() {
  return svg(
    viewBox: '0 0 16 16',
    width: 11.px,
    height: 11.px,
    classes: 'table-row-detail-copy-icon',
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M3.5 8.25 6.5 11.25 12.5 4.75',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
    ],
  );
}

class _DetailFieldValue extends StatelessComponent {
  const _DetailFieldValue({required this.value, required this.shape});

  final String value;
  final ColumnShape? shape;

  bool get _isStructured =>
      shape?.kind == ColumnShapeKind.map || shape?.kind == ColumnShapeKind.list || shape?.kind == ColumnShapeKind.blob;

  bool get _collapsible {
    if (value == '—' || value == '••••••••') return false;
    final kind = shape?.kind;
    if (kind == ColumnShapeKind.text || kind == ColumnShapeKind.email) {
      return value.length > _collapsibleMinLength;
    }
    if (_isStructured) return value.length > _collapsibleMinLength;
    return false;
  }

  @override
  Component build(BuildContext context) {
    if (_collapsible) {
      return _DetailCollapsibleValue(value: value, monospace: _isStructured);
    }

    final valueClass = _isStructured ? 'table-row-detail-value table-row-detail-value--mono' : 'table-row-detail-value';

    return pre(classes: valueClass, [.text(value)]);
  }
}

class _DetailCollapsibleValue extends StatefulComponent {
  const _DetailCollapsibleValue({required this.value, required this.monospace});

  final String value;
  final bool monospace;

  @override
  State<_DetailCollapsibleValue> createState() => _DetailCollapsibleValueState();
}

class _DetailCollapsibleValueState extends State<_DetailCollapsibleValue> {
  var _expanded = false;

  @override
  Component build(BuildContext context) {
    final valueClass = component.monospace
        ? 'table-row-detail-value table-row-detail-value--mono'
        : 'table-row-detail-value';

    return div(classes: 'table-row-detail-collapsible', [
      pre(
        classes: _expanded
            ? '$valueClass table-row-detail-value--expanded'
            : '$valueClass table-row-detail-value--collapsed',
        [.text(component.value)],
      ),
      button(classes: 'table-row-detail-expand', type: .button, onClick: () => setState(() => _expanded = !_expanded), [
        .text(_expanded ? 'Show less' : 'Show more'),
      ]),
    ]);
  }
}

@css
List<StyleRule> get tableRowDetailPanelStyles => [
  css('.table-row-detail-backdrop').styles(
    display: .block,
    position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
    opacity: 0,
    transition: Transition('opacity', duration: _slideDuration, curve: Curve.easeOut),
    raw: const {'z-index': '160', 'background-color': 'rgb(15 23 42 / 0.45)', 'pointer-events': 'none'},
  ),
  css('.table-row-detail-backdrop.table-row-detail--open').styles(opacity: 1, raw: const {'pointer-events': 'auto'}),
  css('.table-row-detail-panel').styles(
    position: Position.fixed(top: 0.px, right: 0.px, bottom: 0.px),
    display: .flex,
    flexDirection: FlexDirection.column,
    minHeight: .zero,
    height: 100.percent,
    overflow: Overflow.hidden,
    border: .only(
      left: BorderSide.solid(color: borderColor, width: 1.px),
    ),
    backgroundColor: surfaceColor,
    transform: Transform.translate(x: 100.percent),
    transition: Transition('transform', duration: _slideDuration, curve: Curve.easeOut),
    raw: const {
      'z-index': '161',
      'min-width': '380px',
      'max-width': '75vw',
      'box-shadow': '-8px 0 24px rgb(15 23 42 / 0.12)',
      'outline': 'none',
      'will-change': 'transform',
    },
  ),
  css('.table-row-detail-panel.table-row-detail--open').styles(transform: Transform.none),
  css(
    '.table-row-detail-panel.table-row-detail--resizing',
  ).styles(userSelect: .none, raw: const {'transition': 'none', 'cursor': 'ew-resize'}),
  css('.table-row-detail-resize-handle').styles(
    position: Position.absolute(top: 0.px, left: 0.px, bottom: 0.px),
    width: 20.px,
    height: 100.percent,
    display: .block,
    padding: .zero,
    margin: .zero,
    border: .none,
    backgroundColor: Colors.transparent,
    raw: const {
      'cursor': 'ew-resize',
      'touch-action': 'none',
      'box-sizing': 'border-box',
      'z-index': '10',
    },
  ),
  css('.table-row-detail-resize-handle:hover').styles(backgroundColor: hoverColor),
  css('.table-row-detail-main').styles(
    flex: Flex(grow: 1, shrink: 1),
    display: .flex,
    flexDirection: FlexDirection.column,
    width: 100.percent,
    minWidth: .zero,
    minHeight: .zero,
    height: 100.percent,
    padding: .only(left: 20.px),
    overflow: Overflow.hidden,
    raw: const {'box-sizing': 'border-box'},
  ),
  css('.table-row-detail-header').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .start,
    justifyContent: .spaceBetween,
    gap: Gap.all(12.px),
    padding: .symmetric(horizontal: 16.px, vertical: 14.px),
    border: .only(
      bottom: BorderSide.solid(color: borderColor, width: 1.px),
    ),
  ),
  css('.table-row-detail-header-text').styles(
    minWidth: .zero,
    flex: Flex(grow: 1, shrink: 1),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(4.px),
  ),
  css('.table-row-detail-title').styles(margin: .zero, fontSize: 0.9375.rem, fontWeight: .w600),
  css('.table-row-detail-subtitle').styles(
    margin: .zero,
    fontSize: 0.75.rem,
    color: mutedColor,
    raw: const {
      'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
      'overflow-wrap': 'anywhere',
      'line-height': '1.35',
    },
  ),
  css('.table-row-detail-header-actions').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(6.px),
    flex: Flex(grow: 0, shrink: 0),
  ),
  css('.table-row-detail-view-toggle').styles(
    padding: .symmetric(horizontal: 10.px, vertical: 6.px),
    margin: .zero,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(8.px)),
    backgroundColor: Colors.transparent,
    color: mutedColor,
    cursor: .pointer,
    fontSize: 0.75.rem,
    fontWeight: .w600,
    raw: const {'font': 'inherit', 'line-height': '1.2'},
  ),
  css('.table-row-detail-view-toggle:hover').styles(backgroundColor: hoverColor, color: fgColor),
  css('.table-row-detail-close').styles(
    width: 32.px,
    height: 32.px,
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    cursor: .pointer,
    radius: .all(Radius.circular(8.px)),
    border: Border.none,
    backgroundColor: Colors.transparent,
    color: mutedColor,
    fontSize: 1.25.rem,
    padding: .zero,
    flex: Flex(grow: 0, shrink: 0),
    raw: const {'font': 'inherit', 'line-height': '1'},
  ),
  css('.table-row-detail-close:hover').styles(backgroundColor: hoverColor, color: fgColor),
  css('.table-row-detail-footer').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    justifyContent: .end,
    padding: .symmetric(horizontal: 16.px, vertical: 12.px),
    border: .only(
      top: BorderSide.solid(color: borderColor, width: 1.px),
    ),
    backgroundColor: surfaceColor,
  ),
  css('.table-row-detail-footer-actions').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    gap: Gap.all(_footerActionsGapPx.px),
    width: _footerContentMaxWidthPx.px,
    maxWidth: _footerContentMaxWidthPx.px,
  ),
  css('.table-row-detail-footer-actions .table-row-detail-footer-btn--primary').styles(
    flex: Flex(grow: 3, shrink: 1),
    width: .auto,
    maxWidth: _footerSaveBtnMaxWidthPx.px,
  ),
  css('.table-row-detail-footer-actions .table-row-detail-footer-btn--cancel').styles(
    flex: Flex(grow: 1, shrink: 1),
    width: .auto,
    maxWidth: _footerCancelBtnMaxWidthPx.px,
  ),
  css('.table-row-detail-footer > .table-row-detail-footer-btn').styles(
    width: _footerContentMaxWidthPx.px,
    maxWidth: _footerContentMaxWidthPx.px,
  ),
  css('.table-row-detail-footer-btn').styles(
    display: .block,
    width: 100.percent,
    padding: .symmetric(horizontal: 16.px, vertical: 10.px),
    border: Border.all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(8.px)),
    backgroundColor: surfaceColor,
    color: fgColor,
    cursor: .pointer,
    fontSize: 0.875.rem,
    fontWeight: .w600,
    textAlign: TextAlign.center,
    raw: const {'font': 'inherit', 'line-height': '1.3', 'box-sizing': 'border-box'},
  ),
  css('.table-row-detail-footer-btn:hover').styles(backgroundColor: hoverColor),
  css('.table-row-detail-footer-btn--primary').styles(
    backgroundColor: primaryColor,
    color: onPrimaryColor,
    border: Border.all(color: primaryColor, width: 1.px, style: .solid),
  ),
  css('.table-row-detail-footer-btn--primary:hover').styles(backgroundColor: primaryHoverColor),
  css('.table-row-detail-footer-btn:disabled').styles(
    opacity: 0.55,
    cursor: .notAllowed,
  ),
  css('.table-row-detail-footer-btn--primary:disabled:hover').styles(backgroundColor: primaryColor),
  css('.table-row-detail-discard-backdrop').styles(
    position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .symmetric(horizontal: 24.px),
    raw: const {
      'z-index': '170',
      'background-color': 'rgb(15 23 42 / 0.55)',
    },
  ),
  css('.table-row-detail-discard-dialog').styles(
    width: 100.percent,
    maxWidth: 400.px,
    padding: .all(20.px),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(16.px),
    backgroundColor: surfaceColor,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(12.px)),
    raw: const {'box-shadow': 'var(--zonai-shadow)'},
  ),
  css('.table-row-detail-discard-title').styles(
    margin: .zero,
    fontSize: 1.rem,
    fontWeight: .w600,
    color: fgColor,
  ),
  css('.table-row-detail-discard-message').styles(
    margin: .zero,
    fontSize: 0.875.rem,
    color: mutedColor,
    raw: const {'line-height': '1.5'},
  ),
  css('.table-row-detail-discard-actions').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    justifyContent: .end,
    gap: Gap.all(8.px),
  ),
  css('.table-row-detail-discard-btn').styles(
    padding: .symmetric(horizontal: 14.px, vertical: 8.px),
    border: Border.all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(8.px)),
    backgroundColor: surfaceColor,
    color: fgColor,
    cursor: .pointer,
    fontSize: 0.875.rem,
    fontWeight: .w600,
    raw: const {'font': 'inherit', 'line-height': '1.3'},
  ),
  css('.table-row-detail-discard-btn:hover').styles(backgroundColor: hoverColor),
  css('.table-row-detail-discard-btn--danger').styles(
    backgroundColor: const Color('#dc2626'),
    color: Colors.white,
    border: Border.all(color: const Color('#dc2626'), width: 1.px, style: .solid),
  ),
  css('.table-row-detail-discard-btn--danger:hover').styles(backgroundColor: const Color('#b91c1c')),
  css('.table-row-detail-body').styles(
    flex: Flex(grow: 1, shrink: 1),
    overflow: Overflow.auto,
    padding: .symmetric(horizontal: 16.px, vertical: 12.px),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(14.px),
    minHeight: .zero,
  ),
  css('.table-row-detail-json-card').styles(
    position: Position.relative(),
    display: .flex,
    flexDirection: FlexDirection.column,
    flex: Flex(grow: 0, shrink: 0),
    alignSelf: .start,
    width: 100.percent,
    radius: .all(Radius.circular(10.px)),
    border: .all(color: const Color('#334155'), width: 1.px, style: .solid),
    backgroundColor: const Color('#0f172a'),
    raw: const {'box-shadow': 'inset 0 1px 0 rgb(148 163 184 / 0.08)'},
  ),
  css('.table-row-detail-json-card-toolbar').styles(
    position: Position.absolute(top: 8.px, right: 8.px),
    display: .flex,
    alignItems: .center,
    justifyContent: .end,
    raw: const {'z-index': '2'},
  ),
  css('.table-row-detail-json-card .table-row-detail-copy').styles(color: const Color('#94a3b8')),
  css(
    '.table-row-detail-json-card .table-row-detail-copy-wrap:hover .table-row-detail-copy',
  ).styles(color: const Color('#e2e8f0')),
  css(
    '.table-row-detail-json-card .table-row-detail-copy-wrap:hover .table-row-detail-copy--copied',
  ).styles(color: const Color('#7dd3fc')),
  css('.table-row-detail-json-card .table-row-detail-copy--copied').styles(color: const Color('#7dd3fc')),
  css('.table-row-detail-json-card-pre').styles(
    margin: .zero,
    padding: .only(top: 36.px, left: 12.px, right: 12.px, bottom: 12.px),
    overflow: Overflow.auto,
    whiteSpace: WhiteSpace.preWrap,
    fontSize: 0.75.rem,
    raw: const {
      'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
      'line-height': '1.5',
      'tab-size': '2',
      'max-height': 'min(24rem, 70vh)',
      'overflow-wrap': 'anywhere',
    },
  ),
  css('.table-row-detail-json-highlight').styles(
    display: .inline,
    margin: .zero,
    padding: .zero,
    color: const Color('#e2e8f0'),
    raw: const {
      'font-family': 'inherit',
      'font-size': 'inherit',
      'line-height': 'inherit',
      'white-space': 'inherit',
      'tab-size': 'inherit',
    },
  ),
  css('.table-row-detail-json-highlight .json-hl-key').styles(color: const Color('#7dd3fc')),
  css('.table-row-detail-json-highlight .json-hl-string').styles(color: const Color('#86efac')),
  css('.table-row-detail-json-highlight .json-hl-number').styles(color: const Color('#fcd34d')),
  css('.table-row-detail-json-highlight .json-hl-bool').styles(color: const Color('#f9a8d4')),
  css('.table-row-detail-json-highlight .json-hl-null').styles(color: const Color('#c4b5fd')),
  css('.table-row-detail-json-highlight .json-hl-punct').styles(color: const Color('#64748b')),
  css('.table-row-detail-json-highlight .json-hl-ws').styles(color: const Color('#e2e8f0')),
  css(
    '.table-row-detail-field',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(4.px), minWidth: .zero),
  css('.table-row-detail-label-row').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(6.px),
    minWidth: .zero,
  ),
  css('.table-row-detail-copy-wrap').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    alignSelf: .center,
    flex: Flex(grow: 0, shrink: 0),
    cursor: .pointer,
    padding: .only(bottom: 2.px),
  ),
  css('.table-row-detail-copy').styles(
    width: 0.6875.rem,
    height: 0.6875.rem,
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .zero,
    margin: .zero,
    color: mutedColor,
    cursor: .pointer,
    outline: Outline(style: OutlineStyle.none),
    raw: const {
      'background': 'transparent',
      'border': 'none',
      'box-shadow': 'none',
    },
  ),
  css('.table-row-detail-copy-wrap:hover .table-row-detail-copy').styles(color: fgColor),
  css('.table-row-detail-copy-wrap:hover .table-row-detail-copy--copied').styles(color: primaryColor),
  css('.table-row-detail-copy--copied').styles(color: primaryColor),
  css('.table-row-detail-copy-icon').styles(
    display: .block,
    flex: Flex(grow: 0, shrink: 0),
    raw: const {
      'animation': 'table-row-detail-copy-icon-pop 0.2s ease-out',
    },
  ),
  css('@keyframes table-row-detail-copy-icon-pop').styles(
    raw: const {
      'from': '{ transform: scale(0.82); opacity: 0.55; }',
      'to': '{ transform: scale(1); opacity: 1; }',
    },
  ),
  css('.table-row-detail-field--edit').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(6.px),
  ),
  css('.table-row-detail-edit-input').styles(
    width: 100.percent,
    padding: .symmetric(horizontal: 10.px, vertical: 8.px),
    border: Border.all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(6.px)),
    backgroundColor: bgColor,
    color: fgColor,
    fontSize: 0.875.rem,
    raw: const {'font': 'inherit', 'line-height': '1.4'},
  ),
  css('.table-row-detail-edit-input:disabled').styles(opacity: 0.6),
  css('.table-row-detail-edit-checkbox').styles(
    width: 16.px,
    height: 16.px,
    cursor: .pointer,
  ),
  css('.table-row-detail-label').styles(
    fontSize: 0.6875.rem,
    fontWeight: .w600,
    color: mutedColor,
    display: .flex,
    alignItems: .center,
    alignSelf: .center,
    raw: const {
      'line-height': '1',
      'text-transform': 'uppercase',
      'letter-spacing': '0.04em',
      'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
    },
  ),
  css('.table-row-detail-label--stacked').styles(
    display: .block,
    width: 100.percent,
    alignSelf: .start,
    textAlign: TextAlign.left,
    margin: .zero,
  ),
  css('.table-row-detail-field--readonly-in-edit').styles(
    cursor: .help,
  ),
  css('.table-row-detail-value').styles(
    margin: .zero,
    fontSize: 0.8125.rem,
    color: fgColor,
    whiteSpace: WhiteSpace.preWrap,
    raw: const {'overflow-wrap': 'anywhere', 'line-height': '1.45'},
  ),
  css(
    '.table-row-detail-value--mono',
  ).styles(raw: const {'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'}),
  css('.table-row-detail-value--collapsed').styles(overflow: Overflow.hidden, raw: const {'max-height': '9.5em'}),
  css(
    '.table-row-detail-collapsible',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(6.px), minWidth: .zero),
  css('.table-row-detail-expand').styles(
    alignSelf: .start,
    padding: .zero,
    margin: .zero,
    border: Border.none,
    backgroundColor: Colors.transparent,
    color: primaryColor,
    cursor: .pointer,
    fontSize: 0.75.rem,
    fontWeight: .w600,
    raw: const {'font': 'inherit'},
  ),
  css('.table-row-detail-expand:hover').styles(color: primaryHoverColor),
];
