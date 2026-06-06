import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

import '../providers/app_tooltip_provider.dart';
import 'syntax_highlighted_code.dart';

/// Read-only code block with copy and optional [opal] syntax highlighting.
class QueryPreviewCard extends StatelessComponent {
  const QueryPreviewCard({
    required this.label,
    required this.text,
    this.highlightLanguage,
    this.showToolbar = true,
    super.key,
  });

  final String label;
  final String text;
  final SyntaxHighlightLanguage? highlightLanguage;
  final bool showToolbar;

  @override
  Component build(BuildContext context) {
    return div(classes: 'table-row-detail-json-card', [
      if (showToolbar)
        div(classes: 'table-row-detail-json-card-toolbar', [CopyPreviewTextButton(label: label, text: text)]),
      pre(
        classes: [
          'table-row-detail-json-card-pre',
          if (!showToolbar) 'table-row-detail-json-card-pre--compact',
        ].join(' '),
        [
          if (highlightLanguage case final language?)
            SyntaxHighlightedCode(source: text, language: language, extraClasses: 'table-row-detail-json-highlight')
          else
            code(classes: 'table-row-detail-json-highlight', [.text(text)]),
        ],
      ),
    ]);
  }
}

class CopyPreviewTextButton extends StatefulComponent {
  const CopyPreviewTextButton({required this.label, required this.text, super.key});

  final String label;
  final String text;

  @override
  State<CopyPreviewTextButton> createState() => _CopyPreviewTextButtonState();
}

class _CopyPreviewTextButtonState extends State<CopyPreviewTextButton> {
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
          'width': '7',
          'height': '7',
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
        d: 'M3.5 8.5 6.5 11.5 12.5 4.5',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
    ],
  );
}
