import 'dart:async';
import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_provider.dart';
import '../constants/button_sizes.dart';
import '../constants/layout.dart';
import '../constants/theme.dart';
import '../providers/app_tooltip_provider.dart';
import '../providers/resolved_collection_provider.dart';
import '../providers/session_user_provider.dart';
import '../providers/table_filter_provider.dart';
import '../providers/table_row_create_provider.dart';
import '../providers/table_row_detail_provider.dart';
import '../providers/app_base_url_provider.dart';
import '../providers/photos_config_provider.dart';
import '../providers/table_rows_provider.dart';
import '../providers/toast_provider.dart';
import '../api/api_client.dart';
import '../utils/photo_edit_value.dart';
import '../utils/resolve_photo_drafts.dart';
import '../utils/dom_event_values.dart';
import '../utils/table_cell_edit.dart';
import '../utils/table_row_edit.dart';
import '../utils/table_row_key.dart';
import '../utils/user_facing_error.dart';
import '../utils/table_rows_json.dart';
import 'app_tooltip_overlay.dart';
import 'query_preview_card.dart';
import 'schema_table_foreign_key_cell.dart';
import 'schema_table_photo_cell.dart';
import 'syntax_highlighted_code.dart';
import 'table_edit/foreign_key_picker_dialog.dart';
import 'theme/theme_components.dart';
import 'table_edit/table_cell_edit_field.dart';
import 'table_edit/table_edit_datetime_field.dart';
import 'table_edit/table_edit_styles.dart';
import '../constants/spacing.dart';

const _collapsibleMinLength = 320;
const _slideDuration = Duration(milliseconds: 250);
const _panelMinWidthPx = 380.0;
const _panelDefaultWidthPx = _panelMinWidthPx * 2;
const _panelMaxWidthFraction = 3 / 4;
const _resizeStripWidthPx = 20.0;

class TableRowDetailPanel extends StatefulComponent {
  const TableRowDetailPanel({super.key});

  @override
  State<TableRowDetailPanel> createState() => _TableRowDetailPanelState();
}

class _TableRowDetailPanelState extends State<TableRowDetailPanel> {
  var _render = false;
  var _open = false;
  var _panelWidthPx = _panelDefaultWidthPx;
  var _resizing = false;
  bool? _lastHadPanel;
  TableRowDetailState? _cachedDetail;
  TableRowCreateState? _cachedCreate;
  Timer? _unmountTimer;
  Timer? _openTimer;
  web.EventListener? _documentKeyListener;
  web.EventListener? _documentResizeMoveListener;
  web.EventListener? _documentResizeUpListener;
  web.EventListener? _handleResizeDownListener;
  web.EventListener? _windowResizeListener;
  web.Element? _resizeBoundPanel;
  var _resizeBindAttempts = 0;
  Timer? _resizeBindTimer;
  var _resizeListenersActive = false;
  var _showRawJson = false;
  String? _rawJsonRowKey;
  var _editing = false;
  var _saving = false;
  var _sendingPasswordReset = false;
  List<Object?>? _draft;
  Map<int, String> _textInputs = {};
  final Set<String> _invalidFkFields = {};
  Set<int> _passwordReplaceColumns = {};
  _PendingDismiss? _pendingDismiss;

  @override
  void initState() {
    super.initState();
    _documentResizeMoveListener = _onDocumentResizeMove.toJS;
    _documentResizeUpListener = _onDocumentResizeUp.toJS;
    _handleResizeDownListener = _onResizeHandleMouseDown.toJS;
    _windowResizeListener = _onWindowResize.toJS;
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

  bool _isMobilePanelViewport([double? viewportWidth]) {
    final vw = viewportWidth ?? _viewportWidthPx();
    return vw <= ZonaiLayout.mobilePanelBreakpointPx;
  }

  double get _panelMaxWidthPx {
    final vw = _viewportWidthPx();
    if (_isMobilePanelViewport(vw)) return vw;
    return math.max(_panelMinWidthPx, vw * _panelMaxWidthFraction);
  }

  void _syncPanelWidthToViewport() {
    final vw = _viewportWidthPx();
    if (_isMobilePanelViewport(vw)) {
      _applyPanelWidthPx(vw);
      return;
    }
    if (_panelWidthPx >= vw * 0.9) {
      _panelWidthPx = _panelDefaultWidthPx.clamp(_panelMinWidthPx, _panelMaxWidthPx);
    }
    _applyPanelWidthPx(_panelWidthPx);
  }

  void _bindWindowResizeListener() {
    final listener = _windowResizeListener;
    if (listener == null || !context.binding.isClient) return;
    web.window.addEventListener('resize', listener);
    web.window.visualViewport?.addEventListener('resize', listener);
  }

  void _unbindWindowResizeListener() {
    final listener = _windowResizeListener;
    if (listener == null) return;
    web.window.removeEventListener('resize', listener);
    web.window.visualViewport?.removeEventListener('resize', listener);
  }

  void _onWindowResize(web.Event event) {
    if (!mounted || !_render || _resizing) return;
    _syncPanelWidthToViewport();
    setState(() {});
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
    _unbindWindowResizeListener();
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
      if (isDatetimePickerPopoverOpen()) return;
      if (isForeignKeyPickerOpen()) return;
      event.preventDefault();
      if (_pendingDismiss != null) {
        setState(() => _pendingDismiss = null);
        return;
      }
      final create = _cachedCreate;
      if (create != null) {
        _requestCreateDismiss(_PendingDismiss.closeCreate);
        return;
      }
      final detail = _cachedDetail;
      if (detail == null) {
        context.read(tableRowDetailProvider.notifier).close();
        return;
      }
      if (_editing) {
        _requestDismiss(detail, _PendingDismiss.cancelEditing);
        return;
      }
      if (detail.canNavigateBack) {
        context.read(tableRowDetailProvider.notifier).pop();
        return;
      }
      _requestDismiss(detail, _PendingDismiss.closePanel);
      return;
    }

    if (event.key == 'Enter' && (event.metaKey || event.ctrlKey)) {
      if (_pendingDismiss != null || _saving) return;
      final create = _cachedCreate;
      if (create != null) {
        if (!_canSubmitCreate(create)) return;
        event.preventDefault();
        _saveCreate(create);
        return;
      }
      if (!_editing) return;
      final detail = _cachedDetail;
      if (detail == null || !_canSubmitEdit(detail)) return;
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
    final vw = _viewportWidthPx();
    final maxWidth = _panelMaxWidthPx;
    final width = _isMobilePanelViewport(vw) ? vw : widthPx.clamp(_panelMinWidthPx, maxWidth);
    _panelWidthPx = width;
    final panel = _resizeBoundPanel;
    if (panel case web.HTMLElement(:final style)) {
      final widthPxRounded = width.round();
      final maxPxRounded = maxWidth.round();
      style.setProperty('width', '${widthPxRounded}px');
      style.setProperty('max-width', '${maxPxRounded}px');
      if (_isMobilePanelViewport(vw)) {
        style.setProperty('min-width', '100%');
        style.setProperty('max-width', '100%');
      } else {
        style.setProperty('min-width', '${_panelMinWidthPx.round()}px');
      }
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
    _syncPanelWidthToViewport();
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
      _bindWindowResizeListener();
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
    _unbindWindowResizeListener();
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
        _cachedCreate = null;
        _showRawJson = false;
        _rawJsonRowKey = null;
        _editing = false;
        _draft = null;
        _textInputs = {};
        _clearFkInvalidFields();
        _passwordReplaceColumns = {};
      });
    });
  }

  void _syncPanelOpen(TableRowDetailState? detail, TableRowCreateState? create) {
    final hasPanel = detail != null || create != null;

    if (create != null) {
      final isNewCreateSession =
          _cachedCreate == null ||
          _cachedCreate!.sqliteName != create.sqliteName ||
          !_columnListsEqual(_cachedCreate!.columns, create.columns);
      _cachedCreate = create;
      if (isNewCreateSession) {
        _cachedDetail = null;
        _draft = initialCreateDraft(create.columnShapes);
        _textInputs = {};
        _clearFkInvalidFields();
        _saving = false;
        _pendingDismiss = null;
        _showRawJson = false;
        _rawJsonRowKey = null;
        _editing = false;
      }
    } else if (detail != null) {
      _cachedCreate = null;
      final prev = _cachedDetail;
      final rowChanged = prev?.rowKey != detail.rowKey;
      final viewChanged = prev?.viewMode != detail.viewMode;
      if (rowChanged) {
        _editing = false;
        _saving = false;
        _draft = null;
        _textInputs = {};
        _clearFkInvalidFields();
        _showRawJson = false;
        _rawJsonRowKey = null;
        _passwordReplaceColumns = {};
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

    if (_lastHadPanel == hasPanel) {
      return;
    }

    if (hasPanel) {
      if (_lastHadPanel != true) {
        context.read(tableFilterProvider.notifier).closePanel();
      }
      if (!_render) {
        scheduleMicrotask(_onOpen);
      } else if (!_open) {
        _unmountTimer?.cancel();
        _openTimer?.cancel();
        scheduleMicrotask(_onOpen);
      }
    } else if (_lastHadPanel == true) {
      scheduleMicrotask(_onClose);
    }

    _lastHadPanel = hasPanel;
  }

  bool _canEditRow(TableRowDetailState detail, Map<String, TableCollectionActions> allActions, bool sessionCanEdit) {
    return canUpdateTableRows(
      allActions: allActions,
      actions: allActions[detail.sqliteName],
      sessionCanEdit: sessionCanEdit,
      sqliteName: detail.sqliteName,
      columns: detail.columns,
      columnShapes: detail.columnShapes,
      row: detail.row,
    );
  }

  bool _isPasswordAuthTable(TableRowDetailState cached) {
    return cached.columnShapes.any((c) => c.kind == ColumnShapeKind.password);
  }

  String? _emailForPasswordReset(TableRowDetailState cached) {
    final emailIndex = cached.columnShapes.indexWhere((c) => c.kind == ColumnShapeKind.email);
    if (emailIndex == -1 || emailIndex >= cached.row.length) return null;
    final value = cached.row[emailIndex];
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<void> _triggerPasswordReset(BuildContext context, TableRowDetailState cached) async {
    final email = _emailForPasswordReset(cached);
    if (email == null) return;
    setState(() => _sendingPasswordReset = true);
    try {
      await context.read(authProvider.notifier).sendResetPassword(email: email);
      if (mounted) {
        context.read(toastProvider.notifier).showSuccess('Password reset email sent to $email');
      }
    } catch (e) {
      if (mounted) {
        context.read(toastProvider.notifier).showError(userFacingError(e));
      }
    } finally {
      if (mounted) setState(() => _sendingPasswordReset = false);
    }
  }

  void _startEditing(TableRowDetailState detail) {
    setState(() {
      _editing = true;
      _draft = [
        for (var i = 0; i < detail.row.length; i++)
          normalizeCellValueForEdit(
            detail.row[i],
            detail.columnShapes.elementAtOrNull(i) ??
                ColumnShape(
                  name: detail.columns.elementAtOrNull(i) ?? 'column_$i',
                  kind: ColumnShapeKind.text,
                  isNullable: true,
                  isPrimaryKey: false,
                  autoIncrement: false,
                  sqlType: 'TEXT',
                ),
          ),
      ];
      _textInputs = {
        for (var i = 0; i < detail.row.length; i++)
          if (_usesTextInput(detail.columnShapes.elementAtOrNull(i)) &&
              !isPasswordColumn(detail.columnShapes.elementAtOrNull(i)!))
            i: cellToEditWireText(detail.row[i], detail.columnShapes.elementAtOrNull(i), revealSecrets: true),
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
          _clearFkInvalidFields();
          _pendingDismiss = null;
          _showRawJson = false;
          _rawJsonRowKey = null;
          _passwordReplaceColumns = {};
        });
      case TableRowDetailViewMode.json:
        if (_showRawJson && _rawJsonRowKey == detail.rowKey && !_editing) return;
        setState(() {
          _editing = false;
          _draft = null;
          _textInputs = {};
          _clearFkInvalidFields();
          _pendingDismiss = null;
          _showRawJson = true;
          _rawJsonRowKey = detail.rowKey;
          _passwordReplaceColumns = {};
        });
      case TableRowDetailViewMode.edit:
        final allActions = context.read(tableCollectionActionsProvider);
        final sessionCanEdit = context.read(sessionUserProvider)?.canEdit == true;
        if (!_canEditRow(detail, allActions, sessionCanEdit)) {
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
      _clearFkInvalidFields();
      _pendingDismiss = null;
      _passwordReplaceColumns = {};
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
        if (usesDraftValueColumn(shape)) {
          if (!cellValuesEqual(detail.row[i], _draft![i], shape)) return true;
        } else {
          final text = _textInputs[i];
          if (text == null) continue;
          try {
            final parsed = parseEditValue(draftValue: _draft![i], textInput: text, shape: shape);
            if (!cellValuesEqual(detail.row[i], parsed, shape)) return true;
          } on FormatException {
            if (text != cellToEditWireText(detail.row[i], shape, revealSecrets: true)) {
              return true;
            }
          }
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

  void _requestNavigateBack(TableRowDetailState detail) {
    if (_saving) return;
    if (!_editing) {
      context.read(tableRowDetailProvider.notifier).pop();
      return;
    }
    _requestDismiss(detail, _PendingDismiss.navigateBack);
  }

  void _executeDismiss(_PendingDismiss action) {
    switch (action) {
      case _PendingDismiss.closePanel:
        context.read(tableRowDetailProvider.notifier).close();
      case _PendingDismiss.cancelEditing:
        _cancelEditing();
      case _PendingDismiss.navigateBack:
        if (_editing) _cancelEditing();
        context.read(tableRowDetailProvider.notifier).pop();
      case _PendingDismiss.closeCreate:
        context.read(tableRowCreateProvider.notifier).close();
        setState(() {
          _draft = null;
          _textInputs = {};
          _clearFkInvalidFields();
          _pendingDismiss = null;
        });
    }
  }

  bool _usesTextInput(ColumnShape? shape) {
    if (shape == null || !isColumnEditable(shape)) return false;
    if (usesDraftValueColumn(shape)) return false;
    return true;
  }

  List<Object?> _parsedDraft(TableRowDetailState detail, [List<Object?>? draftSource]) {
    final draft = draftSource ?? _draft;
    if (draft == null) return detail.row;

    final parsed = List<Object?>.from(draft);
    for (var i = 0; i < detail.row.length; i++) {
      final shape = detail.columnShapes.elementAtOrNull(i);
      if (shape == null || !isColumnEditable(shape)) {
        parsed[i] = detail.row[i];
        continue;
      }
      if (usesDraftValueColumn(shape)) {
        parsed[i] = parseDraftCellValue(draftValue: draft[i], shape: shape);
        continue;
      }
      if (isPasswordColumn(shape)) {
        if (!_passwordReplaceColumns.contains(i)) {
          parsed[i] = detail.row[i];
          continue;
        }
        final text = _textInputs[i];
        if (isPasswordUpdateUnchanged(text, originalValue: detail.row[i], shape: shape)) {
          parsed[i] = detail.row[i];
          continue;
        }
        parsed[i] = parseEditValue(draftValue: draft[i], textInput: text!, shape: shape);
        continue;
      }
      final text = _textInputs[i];
      if (text == null) continue;
      parsed[i] = parseEditValue(draftValue: draft[i], textInput: text, shape: shape);
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
      final isPasswordReplace = isPasswordColumn(shape) ? _passwordReplaceColumns.contains(index) : null;
      return _EditDetailField(
        fieldLabel: label,
        shape: shape,
        value: _draft?[index],
        textValue: _textInputs[index] ?? '',
        disabled: _saving,
        labelId: 'table-row-edit-label-${shape.name}',
        onFkInvalidChanged: isForeignKeyColumn(shape) ? (invalid) => _setFkFieldInvalid(shape.name, invalid) : null,
        isPasswordReplaceMode: isPasswordReplace,
        onEnablePasswordReplace: isPasswordReplace == false
            ? () => setState(() => _passwordReplaceColumns = {..._passwordReplaceColumns, index})
            : null,
        onDraftChanged: (value) {
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
      rawValue: detail.row[index],
      shape: shape,
      readOnlyHint: _editing && !isColumnEditable(shape),
    );
  }

  List<Object?> _parsedCreateDraft(TableRowCreateState create, [List<Object?>? draftSource]) {
    final draft = draftSource ?? _draft ?? initialCreateDraft(create.columnShapes);
    final parsed = List<Object?>.from(draft);
    for (var i = 0; i < create.columns.length; i++) {
      final shape = create.columnShapes.elementAtOrNull(i);
      if (shape == null || !isColumnEditable(shape)) continue;
      if (usesDraftValueColumn(shape)) {
        parsed[i] = parseDraftCellValue(draftValue: draft[i], shape: shape);
        continue;
      }
      parsed[i] = parseEditValue(draftValue: draft[i], textInput: _textInputs[i] ?? '', shape: shape);
    }
    return parsed;
  }

  bool _columnListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _hasUnsavedCreateChanges(TableRowCreateState create) {
    final initial = initialCreateDraft(create.columnShapes);
    final draft = _draft ?? initial;

    for (var i = 0; i < create.columnShapes.length; i++) {
      final shape = create.columnShapes[i];
      if (!isColumnEditable(shape)) continue;

      if (usesDraftValueColumn(shape)) {
        if (!cellValuesEqual(initial[i], draft[i], shape)) return true;
        continue;
      }

      final text = _textInputs[i];
      final initialWire = cellToEditWireText(initial[i], shape);
      if (text != null && text != initialWire) return true;
    }
    return false;
  }

  void _handleCreateCloseRequest() {
    if (!mounted) return;
    context.read(tableRowCreateProvider.notifier).clearCloseRequest();
    _requestCreateDismiss(_PendingDismiss.closeCreate);
  }

  void _requestCreateDismiss(_PendingDismiss action) {
    if (_saving) return;
    final create = _cachedCreate;
    if (create == null) {
      context.read(tableRowCreateProvider.notifier).close();
      return;
    }
    if (_hasUnsavedCreateChanges(create)) {
      setState(() => _pendingDismiss = action);
      return;
    }
    _executeDismiss(action);
  }

  _DiscardDialogMode _discardDialogMode(_PendingDismiss action) {
    return switch (action) {
      _PendingDismiss.closeCreate => _DiscardDialogMode.create,
      _ => _DiscardDialogMode.edit,
    };
  }

  Component _buildCreateField(BuildContext context, TableRowCreateState create, int index) {
    final shape =
        create.columnShapes.elementAtOrNull(index) ??
        ColumnShape(
          name: create.columns.elementAtOrNull(index) ?? 'column_$index',
          kind: ColumnShapeKind.text,
          isNullable: true,
          isPrimaryKey: false,
          autoIncrement: false,
          sqlType: 'TEXT',
        );
    final label = columnShapeHeaderLabel(shape);

    if (isColumnEditable(shape)) {
      return _EditDetailField(
        fieldLabel: label,
        shape: shape,
        value: _draft?[index],
        textValue: _textInputs[index] ?? '',
        disabled: _saving,
        labelId: 'table-row-create-label-${shape.name}',
        onFkInvalidChanged: isForeignKeyColumn(shape) ? (invalid) => _setFkFieldInvalid(shape.name, invalid) : null,
        onDraftChanged: (value) {
          setState(() {
            _draft ??= initialCreateDraft(create.columnShapes);
            _draft![index] = value;
          });
        },
        onTextChanged: (value) {
          setState(() => _textInputs = {..._textInputs, index: value});
        },
      );
    }

    return _DetailField(label: label, rawValue: null, shape: shape, readOnlyHint: true);
  }

  Future<void> _saveCreate(TableRowCreateState create) async {
    if (_saving) return;

    final rawDraft = _draft ?? initialCreateDraft(create.columnShapes);
    setState(() => _saving = true);

    List<Object?> parsedDraft;
    try {
      final photosConfig = context.read(photosConfigProvider);
      final client = context.read(zonaiClientProvider);
      final resolvedDraft = await resolvePhotoDrafts(
        client: client,
        sqliteName: create.sqliteName,
        draft: rawDraft,
        columnShapes: create.columnShapes,
        photosConfig: photosConfig,
      );
      parsedDraft = _parsedCreateDraft(create, resolvedDraft);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.read(toastProvider.notifier).showError(userFacingError(e));
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.read(toastProvider.notifier).showError(userFacingError(e));
      return;
    }

    final object = buildCreateObject(draft: parsedDraft, columns: create.columns, columnShapes: create.columnShapes);

    if (object.isEmpty) {
      setState(() => _saving = false);
      context.read(toastProvider.notifier).showError('Enter at least one field to create a row.');
      return;
    }

    try {
      final record = await context
          .read(tableRowsProvider.notifier)
          .createRow(sqliteName: create.sqliteName, object: object);
      if (!mounted) return;

      final newRow = rowFromRecord(record, create.columns);
      final rowKey = tableRowKey(newRow, create.columnShapes);
      context
          .read(tableRowDetailProvider.notifier)
          .open(
            rowKey: rowKey,
            row: newRow,
            sqliteName: create.sqliteName,
            columns: create.columns,
            columnShapes: create.columnShapes,
          );
      context.read(toastProvider.notifier).showSuccess('Row created');
      setState(() {
        _saving = false;
        _draft = null;
        _textInputs = {};
        _clearFkInvalidFields();
        _cachedCreate = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.read(toastProvider.notifier).showError(userFacingError(e));
    }
  }

  /// True when [rawDraft] had photo uploads that [resolvePhotoDrafts] applied.
  bool _photoDraftsWereResolved(List<Object?> rawDraft, TableRowDetailState detail) {
    for (var i = 0; i < detail.columnShapes.length; i++) {
      final shape = detail.columnShapes.elementAtOrNull(i);
      if (shape == null || !isPhotoColumnKind(shape.kind)) continue;
      if (asPhotoEditValue(rawDraft.elementAtOrNull(i))?.hasPending == true) {
        return true;
      }
    }
    return false;
  }

  Future<void> _saveRow(TableRowDetailState detail) async {
    if (_saving) return;

    final rawDraft = _draft;
    if (rawDraft == null) return;

    setState(() => _saving = true);

    List<Object?> parsedDraft;
    try {
      final photosConfig = context.read(photosConfigProvider);
      final client = context.read(zonaiClientProvider);
      final resolvedDraft = await resolvePhotoDrafts(
        client: client,
        sqliteName: detail.sqliteName,
        draft: rawDraft,
        columnShapes: detail.columnShapes,
        photosConfig: photosConfig,
      );
      await deleteRemovedPhotos(
        client: client,
        originalRow: detail.row,
        resolvedDraft: resolvedDraft,
        columnShapes: detail.columnShapes,
      );
      parsedDraft = _parsedDraft(detail, resolvedDraft);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.read(toastProvider.notifier).showError(userFacingError(e));
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
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
      if (_photoDraftsWereResolved(rawDraft, detail)) {
        if (!mounted) return;
        final detailNotifier = context.read(tableRowDetailProvider.notifier);
        detailNotifier.setViewMode(TableRowDetailViewMode.fields);
        context.read(toastProvider.notifier).showSuccess('Row updated');
        setState(() {
          _editing = false;
          _saving = false;
          _draft = null;
          _textInputs = {};
          _clearFkInvalidFields();
          _passwordReplaceColumns = {};
        });
        return;
      }
      setState(() => _saving = false);
      _cancelEditing();
      return;
    }

    try {
      final record = await context
          .read(tableRowsProvider.notifier)
          .updateRow(
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
        _clearFkInvalidFields();
        _passwordReplaceColumns = {};
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
    final create = context.watch(tableRowCreateProvider);
    _syncPanelOpen(detail, create);
    if (create?.closeRequested == true) {
      scheduleMicrotask(_handleCreateCloseRequest);
    }

    if (!_render) {
      return Component.empty();
    }

    final cachedCreate = _cachedCreate;
    if (cachedCreate != null) {
      return _buildCreatePanel(context, cachedCreate);
    }

    final cached = _cachedDetail;
    if (cached == null) {
      return Component.empty();
    }

    return _buildDetailPanel(context, cached);
  }

  void _setFkFieldInvalid(String fieldName, bool invalid) {
    setState(() {
      if (invalid) {
        _invalidFkFields.add(fieldName);
      } else {
        _invalidFkFields.remove(fieldName);
      }
    });
  }

  void _clearFkInvalidFields() => _invalidFkFields.clear();

  bool _hasInvalidFkReferences() => _invalidFkFields.isNotEmpty;

  bool _canSubmitCreate(TableRowCreateState create) {
    if (_saving || !_hasUnsavedCreateChanges(create) || _hasInvalidFkReferences()) {
      return false;
    }
    final draft = _draft ?? initialCreateDraft(create.columnShapes);
    return remainingCreateRequiredFieldLabels(
      draft: draft,
      textInputs: _textInputs,
      columnShapes: create.columnShapes,
    ).isEmpty;
  }

  bool _canSubmitEdit(TableRowDetailState detail) {
    if (_saving || !_editing || !_hasUnsavedChanges(detail) || _hasInvalidFkReferences()) {
      return false;
    }
    final draft = _draft;
    if (draft == null) return false;
    return remainingEditRequiredFieldLabels(
      draft: draft,
      textInputs: _textInputs,
      columnShapes: detail.columnShapes,
    ).isEmpty;
  }

  Component _buildCreatePanel(BuildContext context, TableRowCreateState create) {
    final canSubmit = _canSubmitCreate(create);
    final draft = _draft ?? initialCreateDraft(create.columnShapes);
    final requiredFields = remainingCreateRequiredFieldLabels(
      draft: draft,
      textInputs: _textInputs,
      columnShapes: create.columnShapes,
    );
    void close() => _requestCreateDismiss(_PendingDismiss.closeCreate);
    final openClass = _open ? ' table-row-detail--open' : '';
    const editingClass = ' table-row-detail--editing';
    final resizeClass = _resizing ? ' table-row-detail--resizing' : '';
    final vw = _viewportWidthPx();
    final isMobile = _isMobilePanelViewport(vw);
    final maxWidth = _panelMaxWidthPx.round();
    final panelStyle = isMobile
        ? 'width: ${vw.round()}px; min-width: 100%; max-width: 100%;'
        : 'width: ${_panelWidthPx.round()}px; min-width: ${_panelMinWidthPx.round()}px; max-width: ${maxWidth}px;';

    return Component.fragment([
      div(
        classes: 'table-row-detail-backdrop$openClass',
        attributes: {'aria-hidden': 'true'},
        events: {'click': (_) => close()},
        [],
      ),
      aside(
        classes: 'table-row-detail-panel$openClass$resizeClass$editingClass',
        attributes: {'aria-label': 'New row', 'tabindex': '-1', 'style': panelStyle},
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
                h2(classes: 'table-row-detail-title', [.text('New row')]),
              ]),
              div(classes: 'table-row-detail-header-actions', [
                ZonaiIconButton(
                  size: ZonaiIconButtonSize.sm,
                  variant: ZonaiIconButtonVariant.ghost,
                  attributes: {'aria-label': 'Close new row panel'},
                  onClick: close,
                  child: .text('×'),
                ),
              ]),
            ]),
            div(classes: 'table-row-detail-body', [
              for (var i = 0; i < create.columns.length; i++) _buildCreateField(context, create, i),
            ]),
            div(classes: 'table-row-detail-footer table-row-detail-footer--create', [
              if (requiredFields.isNotEmpty)
                p(classes: 'table-row-create-required-hint', [.text('Required: ${requiredFields.join(', ')}')]),
              div(classes: 'table-row-detail-footer-actions', [
                button(
                  classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--primary',
                  type: .button,
                  attributes: {'aria-label': 'Create row', if (!canSubmit) 'disabled': 'true'},
                  onClick: canSubmit ? () => _saveCreate(create) : null,
                  [.text(_saving ? 'Creating…' : 'Create')],
                ),
                button(
                  classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--cancel',
                  type: .button,
                  attributes: {'aria-label': 'Cancel creating row', if (_saving) 'disabled': 'true'},
                  onClick: _saving ? null : () => _requestCreateDismiss(_PendingDismiss.closeCreate),
                  [.text('Cancel')],
                ),
              ]),
            ]),
          ]),
        ],
      ),
      if (_pendingDismiss != null)
        _DiscardChangesDialog(
          mode: _discardDialogMode(_pendingDismiss!),
          hasUnsavedChanges: switch (_pendingDismiss) {
            _PendingDismiss.closeCreate => _cachedCreate != null && _hasUnsavedCreateChanges(_cachedCreate!),
            _ => _cachedDetail != null && _hasUnsavedChanges(_cachedDetail!),
          },
          onKeepEditing: () => setState(() => _pendingDismiss = null),
          onDiscard: () {
            final action = _pendingDismiss!;
            setState(() => _pendingDismiss = null);
            _executeDismiss(action);
          },
        ),
    ]);
  }

  Component _buildDetailPanel(BuildContext context, TableRowDetailState cached) {
    final allActions = context.watch(tableCollectionActionsProvider);
    final sessionCanEdit = context.watch(sessionUserProvider)?.canEdit == true;
    final rowEditable = _canEditRow(cached, allActions, sessionCanEdit);
    final canSave = _canSubmitEdit(cached);
    final requiredFields = _editing && _draft != null
        ? remainingEditRequiredFieldLabels(draft: _draft!, textInputs: _textInputs, columnShapes: cached.columnShapes)
        : const <String>[];
    final canResetPassword =
        !_editing && sessionCanEdit && _isPasswordAuthTable(cached) && _emailForPasswordReset(cached) != null;
    void close() => _requestDismiss(cached, _PendingDismiss.closePanel);
    void goBack() => _requestNavigateBack(cached);
    final subtitle = _detailSubtitle(cached);
    final canNavigateBack = cached.canNavigateBack;
    final showRawJson = !_editing && _showRawJson && _rawJsonRowKey == cached.rowKey;
    final openClass = _open ? ' table-row-detail--open' : '';
    final editingClass = _editing ? ' table-row-detail--editing' : '';
    final resizeClass = _resizing ? ' table-row-detail--resizing' : '';
    final vw = _viewportWidthPx();
    final isMobile = _isMobilePanelViewport(vw);
    final maxWidth = _panelMaxWidthPx.round();
    final panelStyle = isMobile
        ? 'width: ${vw.round()}px; min-width: 100%; max-width: 100%;'
        : 'width: ${_panelWidthPx.round()}px; min-width: ${_panelMinWidthPx.round()}px; max-width: ${maxWidth}px;';

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
                div(classes: 'table-row-detail-header-title-row', [
                  if (canNavigateBack)
                    button(
                      classes: 'table-row-detail-back',
                      type: .button,
                      attributes: {'aria-label': 'Back to previous row'},
                      onClick: goBack,
                      [_tableRowDetailBackArrowIcon(), .text('Back')],
                    ),
                  div(classes: 'table-row-detail-header-heading', [
                    h2(classes: 'table-row-detail-title', [.text('Row details')]),
                    if (subtitle.isNotEmpty) p(classes: 'table-row-detail-subtitle', [.text(subtitle)]),
                  ]),
                ]),
              ]),
              div(classes: 'table-row-detail-header-actions', [
                if (!_editing)
                  button(
                    classes: 'table-row-detail-view-toggle',
                    type: .button,
                    attributes: {'aria-label': showRawJson ? 'Show field details' : 'Show raw JSON'},
                    onClick: () {
                      context.read(appTooltipProvider.notifier).hide();
                      final notifier = context.read(tableRowDetailProvider.notifier);
                      notifier.setViewMode(showRawJson ? TableRowDetailViewMode.fields : TableRowDetailViewMode.json);
                    },
                    [.text(showRawJson ? 'Fields' : 'JSON')],
                  ),
                ZonaiIconButton(
                  size: ZonaiIconButtonSize.sm,
                  variant: ZonaiIconButtonVariant.ghost,
                  attributes: {'aria-label': 'Close row details'},
                  onClick: close,
                  child: .text('×'),
                ),
              ]),
            ]),
            div(classes: 'table-row-detail-body', [
              if (showRawJson)
                _RawJsonCard(json: _detailRawJson(cached))
              else
                for (var i = 0; i < cached.row.length; i++) _buildDetailField(context, cached, i),
            ]),
            if ((rowEditable || canResetPassword) && !showRawJson)
              div(classes: ['table-row-detail-footer', if (_editing) 'table-row-detail-footer--create'].join(' '), [
                if (_editing) ...[
                  if (requiredFields.isNotEmpty)
                    p(classes: 'table-row-create-required-hint', [.text('Required: ${requiredFields.join(', ')}')]),
                  div(classes: 'table-row-detail-footer-actions', [
                    button(
                      classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--primary',
                      type: .button,
                      attributes: {'aria-label': 'Save row', if (_saving || !canSave) 'disabled': 'true'},
                      onClick: canSave ? () => _saveRow(cached) : null,
                      [.text(_saving ? 'Saving…' : 'Save')],
                    ),
                    button(
                      classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--cancel',
                      type: .button,
                      attributes: {'aria-label': 'Cancel editing', if (_saving) 'disabled': 'true'},
                      onClick: _saving ? null : () => _requestDismiss(cached, _PendingDismiss.cancelEditing),
                      [.text('Cancel')],
                    ),
                  ]),
                ] else
                  div(classes: 'table-row-detail-footer-actions', [
                    if (rowEditable)
                      button(
                        classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--primary',
                        type: .button,
                        attributes: {'aria-label': 'Edit row'},
                        onClick: () =>
                            context.read(tableRowDetailProvider.notifier).setViewMode(TableRowDetailViewMode.edit),
                        [.text('Edit row')],
                      ),
                    if (canResetPassword)
                      button(
                        classes: 'table-row-detail-footer-btn table-row-detail-footer-btn--cancel',
                        type: .button,
                        attributes: {
                          'aria-label': 'Send password reset email',
                          if (_sendingPasswordReset) 'disabled': 'true',
                        },
                        onClick: _sendingPasswordReset ? null : () => _triggerPasswordReset(context, cached),
                        [.text(_sendingPasswordReset ? 'Sending…' : 'Reset password')],
                      ),
                  ]),
              ]),
          ]),
        ],
      ),
      if (_pendingDismiss != null)
        _DiscardChangesDialog(
          mode: _discardDialogMode(_pendingDismiss!),
          hasUnsavedChanges: switch (_pendingDismiss) {
            _PendingDismiss.closeCreate => _cachedCreate != null && _hasUnsavedCreateChanges(_cachedCreate!),
            _ => _hasUnsavedChanges(cached),
          },
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

enum _PendingDismiss { closePanel, cancelEditing, navigateBack, closeCreate }

enum _DiscardDialogMode { edit, create }

class _DiscardChangesDialog extends StatefulComponent {
  const _DiscardChangesDialog({
    required this.mode,
    required this.hasUnsavedChanges,
    required this.onKeepEditing,
    required this.onDiscard,
  });

  final _DiscardDialogMode mode;
  final bool hasUnsavedChanges;
  final VoidCallback onKeepEditing;
  final VoidCallback onDiscard;

  @override
  State<_DiscardChangesDialog> createState() => _DiscardChangesDialogState();
}

class _DiscardChangesDialogState extends State<_DiscardChangesDialog> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_focusKeepButton);
  }

  void _focusKeepButton() {
    if (!mounted || !context.binding.isClient) return;
    final el = web.document.querySelector('.table-row-detail-discard-btn--keep');
    if (el is web.HTMLElement) el.focus();
  }

  @override
  Component build(BuildContext context) {
    final mode = component.mode;
    final hasUnsavedChanges = component.hasUnsavedChanges;
    final onKeepEditing = component.onKeepEditing;
    final onDiscard = component.onDiscard;
    final title = switch (mode) {
      _DiscardDialogMode.create => 'Stop creating row?',
      _DiscardDialogMode.edit => 'Discard changes?',
    };
    final message = switch ((mode, hasUnsavedChanges)) {
      (_DiscardDialogMode.create, true) => 'You have unsaved changes. If you leave now, this row will not be created.',
      (_DiscardDialogMode.create, false) => 'If you leave now, this row will not be created.',
      (_, true) => 'You have unsaved changes. If you leave now, your edits will be lost.',
      (_, false) => 'If you leave now, your edits will be lost.',
    };
    final keepLabel = switch (mode) {
      _DiscardDialogMode.create => 'Keep creating',
      _DiscardDialogMode.edit => 'Keep editing',
    };

    return div(
      classes: 'table-row-detail-discard-backdrop',
      events: {'click': (_) => onKeepEditing()},
      [
        div(
          classes: 'table-row-detail-discard-dialog',
          attributes: {'role': 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'table-row-detail-discard-title'},
          events: {'click': (event) => event.stopPropagation()},
          [
            h3(id: 'table-row-detail-discard-title', classes: 'table-row-detail-discard-title', [.text(title)]),
            p(classes: 'table-row-detail-discard-message', [.text(message)]),
            div(classes: 'table-row-detail-discard-actions', [
              button(
                classes:
                    'table-row-detail-discard-btn table-row-detail-discard-btn--secondary table-row-detail-discard-btn--keep',
                type: .button,
                onClick: onKeepEditing,
                [.text(keepLabel)],
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
  try {
    return formatDisplayJson(map);
  } on Object {
    return formatDisplayJson({for (final entry in map.entries) entry.key: entry.value?.toString()});
  }
}

class _RawJsonCard extends StatelessComponent {
  const _RawJsonCard({required this.json});

  final String json;

  @override
  Component build(BuildContext context) {
    return QueryPreviewCard(label: 'JSON', text: json, highlightLanguage: SyntaxHighlightLanguage.json);
  }
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
  const _DetailField({required this.label, required this.rawValue, required this.shape, this.readOnlyHint = false});

  final String label;
  final Object? rawValue;
  final ColumnShape shape;
  final bool readOnlyHint;

  String _copyText(String imageBaseUrl) {
    final photoShape = photoShapeForCell(shape: shape, rawValue: rawValue);
    if (photoShape != null) {
      final urls = photoUrlsFromCell(rawValue, photoShape, imageBaseUrl: imageBaseUrl);
      if (urls.isEmpty) return '—';
      return urls.join('\n');
    }
    return formatReadOnlyCell(rawValue, shape, revealSecrets: true);
  }

  @override
  Component build(BuildContext context) {
    final imageBaseUrl = context.watch(appBaseUrlProvider);
    const readOnlyTooltip = 'Read-only';
    final fieldClass = readOnlyHint
        ? 'table-row-detail-field table-row-detail-field--readonly-in-edit'
        : 'table-row-detail-field';

    return div(
      classes: fieldClass,
      events: readOnlyHint
          ? appTooltipEvents(context, text: readOnlyTooltip, placement: AppTooltipPlacement.belowLeft)
          : const {},
      [
        div(classes: 'table-row-detail-label-row', [
          div(classes: 'table-row-detail-label-group', [
            span(classes: 'table-row-detail-label', [.text(label)]),
            if (!readOnlyHint && !isPasswordColumn(shape)) _CopyFieldValueButton(label: label, text: _copyText(imageBaseUrl)),
          ]),
        ]),
        _DetailFieldValue(rawValue: rawValue, shape: shape),
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
    required this.labelId,
    required this.onDraftChanged,
    required this.onTextChanged,
    this.onFkInvalidChanged,
    this.isPasswordReplaceMode,
    this.onEnablePasswordReplace,
  });

  final String fieldLabel;
  final ColumnShape shape;
  final Object? value;
  final String textValue;
  final bool disabled;
  final String labelId;
  final void Function(Object? value) onDraftChanged;
  final void Function(String value) onTextChanged;
  final void Function(bool invalid)? onFkInvalidChanged;
  final bool? isPasswordReplaceMode;
  final VoidCallback? onEnablePasswordReplace;

  @override
  Component build(BuildContext context) {
    final fieldId = 'table-row-edit-${shape.name}';

    return div(classes: 'table-row-detail-field table-row-detail-field--edit', [
      label(id: labelId, htmlFor: fieldId, classes: 'table-row-detail-label table-row-detail-label--stacked', [
        .text(fieldLabel),
      ]),
      TableCellEditField(
        id: fieldId,
        shape: shape,
        value: value,
        textValue: textValue,
        disabled: disabled,
        labelId: labelId,
        onTextChanged: onTextChanged,
        onDraftChanged: onDraftChanged,
        onFkInvalidChanged: onFkInvalidChanged,
        isPasswordReplaceMode: isPasswordReplaceMode,
        onEnablePasswordReplace: onEnablePasswordReplace,
      ),
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
    context
        .read(appTooltipProvider.notifier)
        .show(text: _tooltipText, top: _tooltipTop!, left: _tooltipLeft!, placement: _tooltipPlacement);
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
      context
          .read(appTooltipProvider.notifier)
          .show(text: _tooltipText, top: top, left: left, placement: _tooltipPlacement);
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
      attributes: {'role': 'button', 'tabindex': '0', 'aria-label': _tooltipText},
      events: {
        'click': (_) => _onCopy(),
        'keydown': _onKeyDown,
        'mouseenter': _showTooltip,
        'mouseleave': _hideTooltip,
        'focus': _showTooltip,
        'blur': _hideTooltip,
      },
      [
        span(classes: 'table-row-detail-copy${_copied ? ' table-row-detail-copy--copied' : ''}', [
          _copied ? _checkIconSvg() : _copyIconSvg(),
        ]),
      ],
    );
  }
}

Component _tableRowDetailBackArrowIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 14.px,
    height: 14.px,
    classes: 'table-row-detail-back-icon',
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M10 4l-4 4 4 4',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
    ],
  );
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
  const _DetailFieldValue({required this.rawValue, required this.shape});

  final Object? rawValue;
  final ColumnShape shape;

  @override
  Component build(BuildContext context) {
    if (rawValue == null) {
      return _DetailPlainText(value: formatReadOnlyCell(rawValue, shape));
    }

    if (isForeignKeyColumn(shape) && shape.foreignKey != null) {
      return SchemaTableForeignKeyCell(
        rawValue: rawValue,
        shape: shape,
        onOpenReferencedRow: (context, referenced) {
          context
              .read(tableRowDetailProvider.notifier)
              .pushReferencedRow(
                rowKey: referenced.rowKey,
                row: referenced.row,
                sqliteName: referenced.sqliteName,
                columns: referenced.columns,
                columnShapes: referenced.columnShapes,
              );
        },
      );
    }

    if (shape.isSecret || shape.kind == ColumnShapeKind.password) {
      return _DetailPlainText(value: '••••••••');
    }

    final photoShape = photoShapeForCell(shape: shape, rawValue: rawValue);
    if (photoShape != null) {
      return SchemaTablePhotoCell(rawValue: rawValue, shape: photoShape, size: SchemaTablePhotoSize.detail);
    }

    return switch (shape.kind) {
      ColumnShapeKind.blob when _usesJsonCodeCard(shape, rawValue) => _DetailJsonCodeValue(
        rawValue: rawValue,
        shape: shape,
      ),
      ColumnShapeKind.map => _DetailJsonCodeValue(rawValue: rawValue, shape: shape),
      ColumnShapeKind.list => _detailListValue(rawValue),
      ColumnShapeKind.enum_ => _detailEnumValue(rawValue, shape.enumValues),
      ColumnShapeKind.enumList => _detailEnumListValue(rawValue, shape.enumValues),
      ColumnShapeKind.boolean ||
      ColumnShapeKind.isVerified => ZonaiBooleanCheck(checked: cellEditValueAsBool(rawValue)),
      _ => _DetailPlainText(value: formatReadOnlyCell(rawValue, shape)),
    };
  }

  Component _detailListValue(Object? value) {
    final items = cellValueAsStringList(value);
    if (items.isEmpty) return _DetailPlainText(value: '—');
    return ZonaiTagList(tags: items);
  }

  Component _detailEnumValue(Object? value, List<String> enumValues) {
    final items = cellValueAsStringList(value, enumValues);
    if (items.isEmpty) return _DetailPlainText(value: '—');
    return ZonaiEnumChipRow(values: items);
  }

  Component _detailEnumListValue(Object? value, List<String> enumValues) {
    final items = cellValueAsStringList(value, enumValues);
    if (items.isEmpty) return _DetailPlainText(value: '—');
    return ZonaiEnumChipRow(values: items);
  }
}

bool _usesJsonCodeCard(ColumnShape shape, Object? rawValue) {
  return switch (shape.kind) {
    ColumnShapeKind.map => true,
    ColumnShapeKind.blob => effectiveColumnEditKind(shape, rawValue) == ColumnShapeKind.blob,
    _ => false,
  };
}

class _DetailJsonCodeValue extends StatelessComponent {
  const _DetailJsonCodeValue({required this.rawValue, required this.shape});

  final Object? rawValue;
  final ColumnShape shape;

  @override
  Component build(BuildContext context) {
    final text = cellToEditString(rawValue, shape);
    if (text.isEmpty) return _DetailPlainText(value: '—');

    return div(classes: 'table-row-detail-value-card', [
      QueryPreviewCard(
        label: shape.name,
        text: text,
        highlightLanguage: SyntaxHighlightLanguage.json,
        showToolbar: false,
      ),
    ]);
  }
}

class _DetailPlainText extends StatelessComponent {
  const _DetailPlainText({required this.value});

  final String value;

  bool get _isMono => value.startsWith('{') || value.startsWith('[');

  bool get _collapsible {
    if (value == '—' || value == '••••••••') return false;
    return value.length > _collapsibleMinLength;
  }

  @override
  Component build(BuildContext context) {
    if (_collapsible) {
      return _DetailCollapsibleValue(value: value, monospace: _isMono);
    }

    final valueClass = _isMono ? 'table-row-detail-value table-row-detail-value--mono' : 'table-row-detail-value';

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
    raw: const {'cursor': 'ew-resize', 'touch-action': 'none', 'box-sizing': 'border-box', 'z-index': '10'},
  ),
  css.media(MediaQuery.all(maxWidth: ZonaiLayout.mobilePanelBreakpointPx.px), [
    css('.table-row-detail-panel').styles(width: 100.percent, raw: const {'max-width': '100%', 'min-width': '100%'}),
    css('.table-row-detail-resize-handle').styles(display: .none),
    css('.table-row-detail-footer-actions').styles(flexDirection: FlexDirection.column, alignItems: .stretch),
    css(
      '.table-row-detail-footer-actions .table-row-detail-footer-btn--primary',
    ).styles(flex: Flex(grow: 0, shrink: 0), width: 100.percent),
    css(
      '.table-row-detail-footer-actions .table-row-detail-footer-btn--cancel',
    ).styles(flex: Flex(grow: 0, shrink: 0), width: 100.percent),
  ]),
  css('.table-row-detail-main').styles(
    flex: Flex(grow: 1, shrink: 1),
    display: .flex,
    flexDirection: FlexDirection.column,
    width: 100.percent,
    minWidth: .zero,
    minHeight: .zero,
    height: 100.percent,
    overflow: Overflow.hidden,
    raw: const {'box-sizing': 'border-box'},
  ),
  css('.table-row-detail-header').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .start,
    justifyContent: .spaceBetween,
    gap: Gap.all(ZonaiSpacing.s6),
    padding: .symmetric(horizontal: ZonaiSpacing.s8, vertical: ZonaiSpacing.s7),
    border: .only(
      bottom: BorderSide.solid(color: borderColor, width: 1.px),
    ),
  ),
  css('.table-row-detail-header-text').styles(
    minWidth: .zero,
    flex: Flex(grow: 1, shrink: 1),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s2),
  ),
  css('.table-row-detail-header-title-row').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .start,
    gap: Gap.all(ZonaiSpacing.s4),
    minWidth: .zero,
  ),
  css('.table-row-detail-header-heading').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s2),
    minWidth: .zero,
    flex: Flex(grow: 1, shrink: 1),
  ),
  css('.table-row-detail-back').styles(
    display: .inlineFlex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s2),
    padding: .symmetric(horizontal: ZonaiSpacing.s4, vertical: ZonaiSpacing.s2),
    margin: .zero,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(8.px)),
    backgroundColor: Colors.transparent,
    color: mutedColor,
    cursor: .pointer,
    fontSize: 0.75.rem,
    fontWeight: .w600,
    flex: Flex(grow: 0, shrink: 0),
    raw: const {'font': 'inherit', 'line-height': '1.2'},
  ),
  css(
    '.table-row-detail-back-icon',
  ).styles(display: .block, flex: Flex(grow: 0, shrink: 0), raw: const {'line-height': '0'}),
  css('.table-row-detail-back:hover:not(:disabled)').styles(backgroundColor: hoverColor, color: fgColor),
  css(
    '.table-row-detail-back:focus-visible',
  ).styles(raw: const {'outline': '2px solid var(--zonai-primary)', 'outline-offset': '1px'}),
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
    gap: Gap.all(ZonaiSpacing.s3),
    flex: Flex(grow: 0, shrink: 0),
  ),
  css('.table-row-detail-view-toggle').styles(
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.xs),
    margin: .zero,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.xs))),
    backgroundColor: Colors.transparent,
    color: mutedColor,
    cursor: .pointer,
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.xs),
    fontWeight: .w600,
    raw: const {'font': 'inherit', 'line-height': '1.2'},
  ),
  css('.table-row-detail-view-toggle:hover').styles(backgroundColor: hoverColor, color: fgColor),
  css('.table-row-detail-footer').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    justifyContent: .center,
    minWidth: .zero,
    padding: .symmetric(horizontal: ZonaiSpacing.s8, vertical: ZonaiSpacing.s6),
    border: .only(
      top: BorderSide.solid(color: borderColor, width: 1.px),
    ),
    backgroundColor: surfaceColor,
    raw: const {'box-sizing': 'border-box'},
  ),
  css(
    '.table-row-detail-footer--create',
  ).styles(flexDirection: FlexDirection.column, alignItems: .center, gap: Gap.all(ZonaiSpacing.s3)),
  css('.table-row-create-required-hint').styles(
    margin: .zero,
    fontSize: 0.75.rem,
    fontWeight: .w400,
    color: mutedColor,
    raw: const {
      'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
      'line-height': '1.4',
    },
  ),
  css('.table-row-detail-footer-actions').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    gap: Gap.all(ZonaiSpacing.s4),
    width: 100.percent,
    maxWidth: 500.px,
    minWidth: .zero,
    margin: .symmetric(horizontal: .auto),
  ),
  css(
    '.table-row-detail-footer-actions .table-row-detail-footer-btn--primary',
  ).styles(flex: Flex(grow: 3, shrink: 1), minWidth: .zero),
  css(
    '.table-row-detail-footer-actions .table-row-detail-footer-btn--cancel',
  ).styles(flex: Flex(grow: 1, shrink: 1), minWidth: .zero),
  css('.table-row-detail-footer > .table-row-detail-footer-btn').styles(width: 100.percent, maxWidth: 100.percent),
  css('.table-row-detail-footer-btn').styles(
    display: .block,
    width: 100.percent,
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.sm),
    border: Border.all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.sm))),
    backgroundColor: surfaceColor,
    color: fgColor,
    cursor: .pointer,
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.sm),
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
  css('.table-row-detail-footer-btn:disabled').styles(opacity: 0.55, cursor: .notAllowed),
  css('.table-row-detail-footer-btn--primary:disabled:hover').styles(backgroundColor: primaryColor),
  css('.table-row-detail-discard-backdrop').styles(
    position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .symmetric(horizontal: ZonaiSpacing.s11),
    raw: const {'z-index': '170', 'background-color': 'rgb(15 23 42 / 0.55)'},
  ),
  css('.table-row-detail-discard-dialog').styles(
    width: 100.percent,
    maxWidth: 400.px,
    padding: .all(ZonaiSpacing.s10),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s8),
    backgroundColor: surfaceColor,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(12.px)),
    raw: const {'box-shadow': 'var(--zonai-shadow)'},
  ),
  css('.table-row-detail-discard-title').styles(margin: .zero, fontSize: 1.rem, fontWeight: .w600, color: fgColor),
  css(
    '.table-row-detail-discard-message',
  ).styles(margin: .zero, fontSize: 0.875.rem, color: mutedColor, raw: const {'line-height': '1.5'}),
  css(
    '.table-row-detail-discard-actions',
  ).styles(display: .flex, flexDirection: FlexDirection.row, justifyContent: .end, gap: Gap.all(ZonaiSpacing.s4)),
  css('.table-row-detail-discard-btn').styles(
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.sm),
    border: Border.all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.sm))),
    backgroundColor: surfaceColor,
    color: fgColor,
    cursor: .pointer,
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.sm),
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
    padding: .symmetric(horizontal: ZonaiSpacing.s8, vertical: ZonaiSpacing.s6),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s7),
    minHeight: .zero,
  ),
  css('.table-row-detail-value-card').styles(width: 100.percent, alignSelf: .stretch),
  css('.table-row-detail-value-card .table-row-detail-json-card').styles(width: 100.percent, maxWidth: 100.percent),
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
    position: Position.absolute(top: ZonaiSpacing.s6, right: ZonaiSpacing.s8),
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
    padding: .only(top: ZonaiSpacing.s11, left: ZonaiSpacing.s4, right: ZonaiSpacing.s4, bottom: ZonaiSpacing.s4),
    overflow: Overflow.visible,
    whiteSpace: WhiteSpace.preWrap,
    fontSize: 0.75.rem,
    raw: const {
      'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
      'line-height': '1.5',
      'tab-size': '2',
      'overflow-wrap': 'anywhere',
    },
  ),
  css('.table-row-detail-json-card-pre--compact').styles(
    padding: .symmetric(horizontal: ZonaiSpacing.s4, vertical: ZonaiSpacing.s4),
  ),
  css(
    '.table-row-detail-field',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2), minWidth: .zero),
  css(
    '.table-row-detail-label-row',
  ).styles(display: .flex, flexDirection: FlexDirection.row, alignItems: .center, minWidth: .zero),
  css('.table-row-detail-label-group').styles(
    display: .inlineFlex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s2),
    maxWidth: 100.percent,
    minWidth: .zero,
  ),
  css('.table-row-detail-copy-wrap').styles(
    display: .inlineFlex,
    alignItems: .center,
    justifyContent: .center,
    flex: Flex(grow: 0, shrink: 0),
    cursor: .pointer,
  ),
  css('.table-row-detail-label-group .table-row-detail-copy-wrap').styles(padding: .only(bottom: ZonaiSpacing.s1)),
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
    raw: const {'background': 'transparent', 'border': 'none', 'box-shadow': 'none'},
  ),
  css('.table-row-detail-copy-wrap:hover .table-row-detail-copy').styles(color: fgColor),
  css('.table-row-detail-copy-wrap:hover .table-row-detail-copy--copied').styles(color: primaryColor),
  css('.table-row-detail-copy--copied').styles(color: primaryColor),
  css('.table-row-detail-copy-icon').styles(
    display: .block,
    flex: Flex(grow: 0, shrink: 0),
    raw: const {'animation': 'table-row-detail-copy-icon-pop 0.2s ease-out'},
  ),
  css('@keyframes table-row-detail-copy-icon-pop').styles(
    raw: const {'from': '{ transform: scale(0.82); opacity: 0.55; }', 'to': '{ transform: scale(1); opacity: 1; }'},
  ),
  css(
    '.table-row-detail-field--edit',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s3)),
  css('.table-row-detail-field--edit .z-input').styles(width: 100.percent),
  css('.table-row-detail-field--edit textarea.z-input').styles(raw: const {'resize': 'vertical', 'min-height': '5rem'}),
  css('.table-row-detail-edit-checkbox').styles(width: 16.px, height: 16.px, cursor: .pointer),
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
  css(
    '.table-row-detail-label--stacked',
  ).styles(display: .block, width: 100.percent, alignSelf: .start, textAlign: TextAlign.left, margin: .zero),
  css('.table-row-detail-field--readonly-in-edit').styles(cursor: .help),
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
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s3), minWidth: .zero),
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
  ...schemaTablePhotoCellStyles,
  ...tableEditSharedStyles,
];
