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
import '../providers/table_row_detail_provider.dart';
import '../utils/dom_event_values.dart';
import '../utils/table_rows_json.dart';
import 'app_tooltip_overlay.dart';

const _collapsibleMinLength = 320;
const _slideDuration = Duration(milliseconds: 250);
const _panelMinWidthPx = 380.0;
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
  var _panelWidthPx = _panelMinWidthPx;
  var _resizing = false;
  bool? _lastHadDetail;
  TableRowDetailState? _cachedDetail;
  Timer? _unmountTimer;
  Timer? _openTimer;
  web.EventListener? _escapeKeyListener;
  web.EventListener? _documentResizeMoveListener;
  web.EventListener? _documentResizeUpListener;
  web.EventListener? _handleResizeDownListener;
  web.Element? _resizeBoundPanel;
  var _resizeBindAttempts = 0;
  Timer? _resizeBindTimer;
  var _resizeListenersActive = false;
  var _showRawJson = false;
  String? _rawJsonRowKey;

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
    _unbindEscapeKeyListener();
    _resizeBindTimer?.cancel();
    _unbindResizeHandleDom();
    _endResizeDrag();
    super.dispose();
  }

  void _bindEscapeKeyListener() {
    if (_escapeKeyListener != null || !context.binding.isClient) return;
    _escapeKeyListener = _onDocumentEscapeKeyDown.toJS;
    web.document.addEventListener('keydown', _escapeKeyListener);
  }

  void _unbindEscapeKeyListener() {
    final listener = _escapeKeyListener;
    if (listener == null) return;
    web.document.removeEventListener('keydown', listener);
    _escapeKeyListener = null;
  }

  void _onDocumentEscapeKeyDown(web.Event event) {
    if (event is! web.KeyboardEvent || event.key != 'Escape') return;
    if (!mounted || !_open) return;
    event.preventDefault();
    context.read(tableRowDetailProvider.notifier).close();
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
      _bindEscapeKeyListener();
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
    _unbindEscapeKeyListener();
    _unbindResizeHandleDom();
    _endResizeDrag();
    setState(() {
      _open = false;
      _resizing = false;
      _showRawJson = false;
      _rawJsonRowKey = null;
    });
    _unmountTimer?.cancel();
    _unmountTimer = Timer(_slideDuration, () {
      if (!mounted) return;
      setState(() {
        _render = false;
        _cachedDetail = null;
      });
    });
  }

  void _syncDetail(TableRowDetailState? detail) {
    final hasDetail = detail != null;
    if (hasDetail) {
      _cachedDetail = detail;
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
    void close() => context.read(tableRowDetailProvider.notifier).close();
    final subtitle = _detailSubtitle(cached);
    final showRawJson = _showRawJson && _rawJsonRowKey == cached.rowKey;
    final openClass = _open ? ' table-row-detail--open' : '';
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
        classes: 'table-row-detail-panel$openClass$resizeClass',
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
                button(
                  classes: 'table-row-detail-view-toggle',
                  type: .button,
                  attributes: {
                    'aria-label': showRawJson ? 'Show field details' : 'Show raw JSON',
                  },
                  onClick: () {
                    context.read(appTooltipProvider.notifier).hide();
                    setState(() {
                      if (showRawJson) {
                        _showRawJson = false;
                        _rawJsonRowKey = null;
                      } else {
                        _showRawJson = true;
                        _rawJsonRowKey = cached.rowKey;
                      }
                    });
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
              if (showRawJson) _RawJsonCard(json: _detailRawJson(cached)) else
                for (var i = 0; i < cached.row.length; i++)
                  _DetailField(
                    label: columnShapeHeaderLabel(
                      cached.columnShapes.elementAtOrNull(i) ??
                          ColumnShape(
                            name: cached.columns.elementAtOrNull(i) ?? 'column_$i',
                            kind: ColumnShapeKind.text,
                            isNullable: true,
                            isPrimaryKey: false,
                            autoIncrement: false,
                            sqlType: 'TEXT',
                          ),
                    ),
                    value: formatSchemaCell(cached.row[i], cached.columnShapes.elementAtOrNull(i), truncate: false),
                    shape: cached.columnShapes.elementAtOrNull(i),
                  ),
            ]),
          ]),
        ],
      ),
    ]);
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
  const _DetailField({required this.label, required this.value, required this.shape});

  final String label;
  final String value;
  final ColumnShape? shape;

  @override
  Component build(BuildContext context) {
    return div(classes: 'table-row-detail-field', [
      div(classes: 'table-row-detail-label-row', [
        span(classes: 'table-row-detail-label', [.text(label)]),
        _CopyFieldValueButton(label: label, text: value),
      ]),
      _DetailFieldValue(value: value, shape: shape),
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
