import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../constants/theme.dart';
import '../providers/table_row_detail_provider.dart';

const _collapsibleMinLength = 320;
const _slideDuration = Duration(milliseconds: 250);

class TableRowDetailPanel extends StatefulComponent {
  const TableRowDetailPanel({super.key});

  @override
  State<TableRowDetailPanel> createState() => _TableRowDetailPanelState();
}

class _TableRowDetailPanelState extends State<TableRowDetailPanel> {
  var _render = false;
  var _open = false;
  bool? _lastHadDetail;
  TableRowDetailState? _cachedDetail;
  Timer? _unmountTimer;
  Timer? _openTimer;

  @override
  void dispose() {
    _unmountTimer?.cancel();
    _openTimer?.cancel();
    super.dispose();
  }

  void _onKeyDown(web.Event event) {
    if (event is! web.KeyboardEvent) return;
    if (event.key != 'Escape') return;
    context.read(tableRowDetailProvider.notifier).close();
  }

  void _focusPanel() {
    if (!context.binding.isClient || !mounted) return;
    final el = web.document.querySelector('.table-row-detail-panel');
    if (el is web.HTMLElement) {
      el.focus();
    }
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
      scheduleMicrotask(_focusPanel);
    });
  }

  void _onClose() {
    if (!_render) return;
    _openTimer?.cancel();
    setState(() => _open = false);
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
    final openClass = _open ? ' table-row-detail--open' : '';

    return Component.fragment([
      div(
        classes: 'table-row-detail-backdrop$openClass',
        attributes: {'aria-hidden': 'true'},
        events: {'click': (_) => close()},
        [],
      ),
      aside(
        classes: 'table-row-detail-panel$openClass',
        attributes: {
          'aria-label': 'Row details',
          'tabindex': '-1',
        },
        events: {
          'click': (event) => event.stopPropagation(),
          'keydown': _onKeyDown,
        },
        [
          div(classes: 'table-row-detail-header', [
            div(classes: 'table-row-detail-header-text', [
              h2(classes: 'table-row-detail-title', [.text('Row details')]),
              if (subtitle.isNotEmpty)
                p(classes: 'table-row-detail-subtitle', [.text(subtitle)]),
            ]),
            button(
              classes: 'table-row-detail-close',
              type: .button,
              attributes: {'aria-label': 'Close row details'},
              onClick: close,
              [.text('×')],
            ),
          ]),
          div(classes: 'table-row-detail-body', [
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
                value: formatSchemaCell(
                  cached.row[i],
                  cached.columnShapes.elementAtOrNull(i),
                  truncate: false,
                ),
                shape: cached.columnShapes.elementAtOrNull(i),
              ),
          ]),
        ],
      ),
    ]);
  }
}

String _detailSubtitle(TableRowDetailState detail) {
  final pkShapes = detail.columnShapes.where((shape) => shape.isPrimaryKey).toList();
  if (pkShapes.isEmpty) return '';

  final parts = <String>[];
  for (final shape in pkShapes) {
    final index = detail.columns.indexOf(shape.name);
    if (index < 0) continue;
    parts.add(
      '${shape.name}=${formatSchemaCell(detail.row[index], shape, truncate: false)}',
    );
  }
  return parts.join(' · ');
}

class _DetailField extends StatelessComponent {
  const _DetailField({
    required this.label,
    required this.value,
    required this.shape,
  });

  final String label;
  final String value;
  final ColumnShape? shape;

  @override
  Component build(BuildContext context) {
    return div(classes: 'table-row-detail-field', [
      span(classes: 'table-row-detail-label', [.text(label)]),
      _DetailFieldValue(value: value, shape: shape),
    ]);
  }
}

class _DetailFieldValue extends StatelessComponent {
  const _DetailFieldValue({required this.value, required this.shape});

  final String value;
  final ColumnShape? shape;

  bool get _isStructured =>
      shape?.kind == ColumnShapeKind.map ||
      shape?.kind == ColumnShapeKind.list ||
      shape?.kind == ColumnShapeKind.blob;

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
      return _DetailCollapsibleValue(
        value: value,
        monospace: _isStructured,
      );
    }

    final valueClass = _isStructured
        ? 'table-row-detail-value table-row-detail-value--mono'
        : 'table-row-detail-value';

    return pre(classes: valueClass, [.text(value)]);
  }
}

class _DetailCollapsibleValue extends StatefulComponent {
  const _DetailCollapsibleValue({
    required this.value,
    required this.monospace,
  });

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
      button(
        classes: 'table-row-detail-expand',
        type: .button,
        onClick: () => setState(() => _expanded = !_expanded),
        [.text(_expanded ? 'Show less' : 'Show more')],
      ),
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
    raw: const {
      'z-index': '160',
      'background-color': 'rgb(15 23 42 / 0.45)',
      'pointer-events': 'none',
    },
  ),
  css('.table-row-detail-backdrop.table-row-detail--open').styles(
    opacity: 1,
    raw: const {'pointer-events': 'auto'},
  ),
  css('.table-row-detail-panel').styles(
    position: Position.fixed(top: 0.px, right: 0.px, bottom: 0.px),
    width: 380.px,
    display: .flex,
    flexDirection: FlexDirection.column,
    minHeight: .zero,
    overflow: Overflow.hidden,
    border: .only(
      left: BorderSide.solid(color: borderColor, width: 1.px),
    ),
    backgroundColor: surfaceColor,
    transform: Transform.translate(x: 100.percent),
    transition: Transition('transform', duration: _slideDuration, curve: Curve.easeOut),
    raw: const {
      'z-index': '161',
      'max-width': 'min(92vw, 480px)',
      'box-shadow': '-8px 0 24px rgb(15 23 42 / 0.12)',
      'outline': 'none',
      'will-change': 'transform',
    },
  ),
  css('.table-row-detail-panel.table-row-detail--open').styles(
    transform: Transform.none,
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
  css('.table-row-detail-title').styles(
    margin: .zero,
    fontSize: 0.9375.rem,
    fontWeight: .w600,
  ),
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
  css('.table-row-detail-field').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(4.px),
    minWidth: .zero,
  ),
  css('.table-row-detail-label').styles(
    fontSize: 0.6875.rem,
    fontWeight: .w600,
    color: mutedColor,
    raw: const {
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
  css('.table-row-detail-value--mono').styles(
    raw: const {'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'},
  ),
  css('.table-row-detail-value--collapsed').styles(
    overflow: Overflow.hidden,
    raw: const {'max-height': '9.5em'},
  ),
  css('.table-row-detail-collapsible').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(6.px),
    minWidth: .zero,
  ),
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
