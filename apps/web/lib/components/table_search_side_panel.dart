import 'dart:async';
import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../constants/layout.dart';
import '../providers/app_tooltip_provider.dart';
import '../utils/dom_event_values.dart';
import '../providers/table_filter_provider.dart';
import '../providers/table_focus_provider.dart';
import '../providers/table_schema_provider.dart';
import 'app_tooltip_overlay.dart';
import 'table_edit/table_edit_datetime_field.dart';
import 'table_edit/foreign_key_picker_dialog.dart';
import 'table_search_panel.dart';
import 'theme/zonai_icon_button.dart';
import '../constants/button_sizes.dart';

const _slideDuration = Duration(milliseconds: 250);
const _panelMinWidthPx = 320.0;
const _panelDefaultWidthFraction = 0.25;
const _panelMaxWidthFraction = 3 / 4;
class TableSearchSidePanel extends StatefulComponent {
  const TableSearchSidePanel({super.key});

  @override
  State<TableSearchSidePanel> createState() => _TableSearchSidePanelState();
}

class _TableSearchSidePanelState extends State<TableSearchSidePanel> {
  var _render = false;
  var _open = false;
  var _panelWidthPx = _panelMinWidthPx;
  var _panelWidthInitialized = false;
  var _resizing = false;
  var _lastPanelOpen = false;
  Timer? _unmountTimer;
  Timer? _openTimer;
  web.EventListener? _documentResizeMoveListener;
  web.EventListener? _documentResizeUpListener;
  web.EventListener? _handleResizeDownListener;
  web.EventListener? _documentKeyListener;
  web.EventListener? _windowResizeListener;
  web.Element? _resizeBoundPanel;
  var _resizeListenersActive = false;

  @override
  void initState() {
    super.initState();
    _documentResizeMoveListener = _onDocumentResizeMove.toJS;
    _documentResizeUpListener = _onDocumentResizeUp.toJS;
    _handleResizeDownListener = _onResizeHandleMouseDown.toJS;
    _documentKeyListener = _onDocumentKeyDown.toJS;
    _windowResizeListener = _onWindowResize.toJS;
  }

  @override
  void dispose() {
    _unmountTimer?.cancel();
    _openTimer?.cancel();
    _unbindDocumentKeyListener();
    _unbindWindowResizeListener();
    _endResizeDrag();
    super.dispose();
  }

  void _bindDocumentKeyListener() {
    if (_documentKeyListener == null || !context.binding.isClient) return;
    web.document.addEventListener('keydown', _documentKeyListener);
  }

  void _unbindDocumentKeyListener() {
    final listener = _documentKeyListener;
    if (listener == null) return;
    web.document.removeEventListener('keydown', listener);
  }

  void _onDocumentKeyDown(web.Event event) {
    if (event is! web.KeyboardEvent) return;
    if (!mounted || !_open) return;

    if (event.key == 'Enter' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      _applyFilter();
      return;
    }

    if (event.key != 'Escape') return;
    if (_isDatetimePickerOpenInPanel()) return;
    if (isForeignKeyPickerOpen()) return;

    event.preventDefault();
    context.read(tableFilterProvider.notifier).closePanel();
  }

  void _applyFilter() {
    final notifier = context.read(tableFilterProvider.notifier);
    if (notifier.apply()) {
      notifier.closePanel();
    }
  }

  bool _isDatetimePickerOpenInPanel() => isDatetimePickerPopoverOpen();

  double _viewportWidthPx() {
    final vv = web.window.visualViewport;
    if (vv != null) {
      final w = jsNumProperty(vv, 'width');
      if (w > 0) return w;
    }
    final iw = jsNumProperty(web.window, 'innerWidth');
    if (iw > 0) return iw;
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

  double _defaultPanelWidthPx() {
    final viewport = _viewportWidthPx();
    if (_isMobilePanelViewport(viewport)) return viewport;
    return (viewport * _panelDefaultWidthFraction).clamp(_panelMinWidthPx, _panelMaxWidthPx);
  }

  void _ensureDefaultPanelWidth() {
    if (_panelWidthInitialized) return;
    _panelWidthInitialized = true;
    _panelWidthPx = _defaultPanelWidthPx();
  }

  double _panelRightEdgePx() {
    final panel = _resizeBoundPanel;
    if (panel != null) {
      final r = panel.getBoundingClientRect().right;
      if (r > 0) return r.toDouble();
    }
    return _viewportWidthPx();
  }

  void _applyPanelWidthPx(double widthPx) {
    final vw = _viewportWidthPx();
    final width = _isMobilePanelViewport(vw) ? vw : widthPx.clamp(_panelMinWidthPx, _panelMaxWidthPx);
    _panelWidthPx = width;
    if (_resizeBoundPanel case web.HTMLElement(:final style)) {
      style.setProperty('width', '${width.round()}px');
      style.setProperty('max-width', '${_panelMaxWidthPx.round()}px');
      style.setProperty('min-width', '${_panelMinWidthPx.round()}px');
      if (_isMobilePanelViewport(vw)) {
        style.setProperty('min-width', '100%');
        style.setProperty('max-width', '100%');
      }
    }
  }

  void _syncPanelLayoutToViewport() {
    final vw = _viewportWidthPx();
    if (_isMobilePanelViewport(vw)) {
      _applyPanelWidthPx(vw);
      return;
    }
    if (_panelWidthPx >= vw * 0.9) {
      _panelWidthPx = _defaultPanelWidthPx();
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
    _syncPanelLayoutToViewport();
    setState(() {});
  }

  void _applyResizeFromClientX(double clientX) {
    _applyPanelWidthPx(_panelRightEdgePx() - clientX);
  }

  void _onResizeHandleMouseDown(web.Event event) {
    if (!mounted || !context.binding.isClient || _resizeListenersActive) return;
    event.preventDefault();
    event.stopPropagation();
    _resizeBoundPanel ??= web.document.querySelector('.table-search-side-panel');
    final clientX = _eventClientX(event);
    if (clientX == null || _resizeBoundPanel == null) return;
    _resizing = true;
    _resizeListenersActive = true;
    _applyResizeFromClientX(clientX);
    _setResizeCursor(active: true);
    final move = _documentResizeMoveListener;
    final up = _documentResizeUpListener;
    if (move != null && up != null) {
      web.document.addEventListener('mousemove', move);
      web.document.addEventListener('mouseup', up);
      web.document.addEventListener('pointermove', move);
      web.document.addEventListener('pointerup', up);
    }
  }

  void _onDocumentResizeMove(web.Event event) {
    if (!mounted || !_resizeListenersActive) return;
    final x = _eventClientX(event);
    if (x != null) _applyResizeFromClientX(x);
  }

  void _onDocumentResizeUp(web.Event event) {
    if (!mounted) return;
    _endResizeDrag();
    setState(() => _resizing = false);
  }

  void _endResizeDrag() {
    final body = web.document.body;
    if (body != null) {
      body.style.cursor = '';
      body.style.removeProperty('user-select');
    }
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
    }
    _resizeListenersActive = false;
  }

  void _setResizeCursor({required bool active}) {
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

  double? _eventClientX(web.Event event) => eventClientX(event);

  void _onOpen() {
    _unmountTimer?.cancel();
    _openTimer?.cancel();
    _ensureDefaultPanelWidth();
    setState(() {
      _render = true;
      _open = false;
    });
    _openTimer = Timer(const Duration(milliseconds: 20), () {
      if (!mounted) return;
      setState(() => _open = true);
      _bindDocumentKeyListener();
      _bindWindowResizeListener();
      scheduleMicrotask(_bindResizeDom);
    });
  }

  void _onClose() {
    if (!_render) return;
    _openTimer?.cancel();
    if (context.binding.isClient) {
      context.read(appTooltipProvider.notifier).hide();
    }
    _unbindDocumentKeyListener();
    _unbindWindowResizeListener();
    _endResizeDrag();
    setState(() {
      _open = false;
      _resizing = false;
    });
    _unmountTimer?.cancel();
    _unmountTimer = Timer(_slideDuration, () {
      if (!mounted) return;
      setState(() => _render = false);
    });
  }

  void _bindResizeDom() {
    if (!mounted || !_open) return;
    final panel = web.document.querySelector('.table-search-side-panel.table-search--open');
    if (panel is! web.HTMLElement) return;
    _resizeBoundPanel = panel;
    _applyPanelWidthPx(_panelWidthPx);
    final handle = panel.querySelector('.table-search-resize-handle');
    final down = _handleResizeDownListener;
    if (handle is web.HTMLElement && down != null) {
      handle.addEventListener('mousedown', down);
      handle.addEventListener('pointerdown', down);
    }
  }

  void _syncPanel(bool panelOpen) {
    if (_lastPanelOpen == panelOpen) return;

    if (panelOpen) {
      if (!_render) {
        scheduleMicrotask(_onOpen);
      } else if (!_open) {
        _unmountTimer?.cancel();
        scheduleMicrotask(_onOpen);
      }
    } else if (_lastPanelOpen) {
      scheduleMicrotask(_onClose);
    }

    _lastPanelOpen = panelOpen;
  }

  @override
  Component build(BuildContext context) {
    if (!context.binding.isClient) return Component.empty();

    final filter = context.watch(tableFilterProvider);
    _syncPanel(filter.panelOpen);

    if (!_render) return Component.empty();

    final schema = context.watch(tableSchemaProvider);
    final shapes = schema?.columns ?? const <ColumnShape>[];
    final tableName = context.watch(tableFocusProvider)?.sqliteName ?? '';
    final summary = tableFilterPanelSummary(filter, shapes);
    final openClass = _open ? ' table-search--open' : '';
    final resizeClass = _resizing ? ' table-search--resizing' : '';
    final vw = _viewportWidthPx();
    final isMobile = _isMobilePanelViewport(vw);
    final panelStyle = isMobile
        ? 'width: ${vw.round()}px; min-width: 100%; max-width: 100%;'
        : 'width: ${_panelWidthPx.round()}px; min-width: ${_panelMinWidthPx.round()}px; max-width: ${_panelMaxWidthPx.round()}px;';
    final close = () => context.read(tableFilterProvider.notifier).closePanel();

    return Component.fragment([
      div(
        classes: 'table-search-backdrop$openClass',
        attributes: {'aria-hidden': 'true'},
        events: {'click': (_) => close()},
        [],
      ),
      aside(
        classes: 'table-search-side-panel$openClass$resizeClass',
        attributes: {'aria-label': 'Search and filter', 'tabindex': '-1', 'style': panelStyle},
        events: {'click': (e) => e.stopPropagation()},
        [
          div(
            classes: 'table-search-resize-handle',
            events: {
              'mousedown': _onResizeHandleMouseDown,
              'pointerdown': _onResizeHandleMouseDown,
              ...appTooltipEvents(context, text: 'Drag to resize'),
            },
            [],
          ),
          div(classes: 'table-search-side-main', [
            div(classes: 'table-search-side-header', [
              div(classes: 'table-search-side-header-row', [
                h2(classes: 'table-search-side-title', [.text('Search')]),
                ZonaiIconButton(
                  size: ZonaiIconButtonSize.sm,
                  attributes: {'aria-label': 'Close search panel'},
                  onClick: close,
                  child: removeConditionIcon(),
                ),
              ]),
              if (summary != null) p(classes: 'table-search-side-summary', [.text(summary)]),
            ]),
            if (shapes.isNotEmpty && tableName.isNotEmpty)
              TableSearchPanel(columnShapes: shapes, state: filter, tableName: tableName)
            else
              div(classes: 'table-search-panel-body', [
                p(classes: 'table-search-side-summary', [.text('Load table schema to build filters.')]),
              ]),
          ]),
        ],
      ),
    ]);
  }
}
