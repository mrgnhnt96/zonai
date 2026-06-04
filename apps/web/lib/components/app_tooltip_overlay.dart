import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../constants/theme.dart';
import '../providers/app_tooltip_provider.dart';

void showAppTooltipForElement(
  AppTooltipNotifier notifier, {
  required web.Element anchor,
  required String text,
  AppTooltipPlacement placement = AppTooltipPlacement.belowCenter,
}) {
  final rect = anchor.getBoundingClientRect();
  final (top, left) = switch (placement) {
    AppTooltipPlacement.belowCenter => (rect.bottom + 6, rect.left + rect.width / 2),
    AppTooltipPlacement.rightCenter => (rect.top + rect.height / 2, rect.right + 8),
  };
  notifier.show(text: text, top: top, left: left, placement: placement);
}

void showAppTooltipFromEvent(
  web.Event event,
  AppTooltipNotifier notifier, {
  required String text,
  AppTooltipPlacement placement = AppTooltipPlacement.belowCenter,
  String? anchorSelector,
}) {
  final el = event.currentTarget;
  if (el is! web.HTMLElement) return;
  var anchor = el as web.Element;
  if (anchorSelector != null) {
    final found = el.querySelector(anchorSelector);
    if (found != null) anchor = found;
  }
  showAppTooltipForElement(notifier, anchor: anchor, text: text, placement: placement);
}

Map<String, void Function(web.Event)> appTooltipEvents(
  BuildContext context, {
  required String text,
  AppTooltipPlacement placement = AppTooltipPlacement.belowCenter,
  String? anchorSelector,
}) {
  final notifier = context.read(appTooltipProvider.notifier);
  return {
    'mouseenter': (event) => showAppTooltipFromEvent(
      event,
      notifier,
      text: text,
      placement: placement,
      anchorSelector: anchorSelector,
    ),
    'mouseleave': (_) => notifier.hide(),
    'focus': (event) => showAppTooltipFromEvent(
      event,
      notifier,
      text: text,
      placement: placement,
      anchorSelector: anchorSelector,
    ),
    'blur': (_) => notifier.hide(),
  };
}

/// Single floating tooltip host for the app shell.
class AppTooltipOverlay extends StatelessComponent {
  const AppTooltipOverlay({super.key});

  @override
  Component build(BuildContext context) {
    if (!context.binding.isClient) return Component.empty();

    final tooltip = context.watch(appTooltipProvider);
    final visible = tooltip.text != null;
    final transform = switch (tooltip.placement) {
      AppTooltipPlacement.belowCenter => 'translateX(-50%)',
      AppTooltipPlacement.rightCenter => 'translateY(-50%)',
    };

    return span(
      classes: 'app-tooltip${visible ? ' app-tooltip--visible' : ''}',
      attributes: {
        'role': 'tooltip',
        if (visible)
          'style': 'top: ${tooltip.top}px; left: ${tooltip.left}px; transform: $transform;',
      },
      [if (visible) .text(tooltip.text!)],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.app-tooltip').styles(
      padding: .symmetric(horizontal: 10.px, vertical: 6.px),
      radius: .all(Radius.circular(6.px)),
      backgroundColor: surfaceColor,
      border: .all(color: borderColor, width: 1.px, style: .solid),
      fontSize: 0.8125.rem,
      fontWeight: .w500,
      color: fgColor,
      pointerEvents: .none,
      raw: const {
        'position': 'fixed',
        'white-space': 'nowrap',
        'z-index': '400',
        'box-shadow': 'var(--zonai-shadow-sm)',
        'opacity': '0',
        'visibility': 'hidden',
        'transition': 'opacity 0.15s ease, visibility 0.15s ease',
      },
    ),
    css('.app-tooltip--visible').styles(raw: const {'opacity': '1', 'visibility': 'visible'}),
  ];
}
