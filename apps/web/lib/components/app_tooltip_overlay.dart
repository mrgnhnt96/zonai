import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../constants/theme.dart';
import '../providers/app_tooltip_provider.dart';
import '../constants/spacing.dart';

void showAppTooltipForElement(
  AppTooltipNotifier notifier, {
  required web.Element anchor,
  required String text,
  AppTooltipPlacement placement = AppTooltipPlacement.belowCenter,
}) {
  final rect = anchor.getBoundingClientRect();

  // A `below*` tooltip on an anchor near the bottom of the window renders past
  // the bottom edge. It is `position: fixed`, so no ancestor clips it and
  // nothing scrolls it back into view -- it is simply not there. The last
  // actions in the row detail panel sit exactly that low.
  //
  // Flipping needs the tooltip's height, which does not exist until it
  // renders, so the test is against a constant instead: one line of 0.8125rem
  // text between 6px paddings inside a 1px border is ~30px, and the offset
  // below adds 6. 44 leaves room for both plus a little slack, and erring
  // toward flipping early is the safe direction -- above the anchor there is
  // a whole panel of space, below there is none.
  final flip = web.window.innerHeight - rect.bottom < 44;
  final resolved = switch (placement) {
    AppTooltipPlacement.belowCenter when flip => AppTooltipPlacement.aboveCenter,
    AppTooltipPlacement.belowLeft when flip => AppTooltipPlacement.aboveLeft,
    _ => placement,
  };

  // The `above*` pair anchors at the anchor's TOP and is pulled up by its own
  // height in CSS (`translateY(-100%)`), which is what lets this run without
  // ever measuring the tooltip.
  final (top, left) = switch (resolved) {
    AppTooltipPlacement.belowCenter => (rect.bottom + 6, rect.left + rect.width / 2),
    AppTooltipPlacement.belowLeft => (rect.bottom + 6, rect.left),
    AppTooltipPlacement.aboveCenter => (rect.top - 6, rect.left + rect.width / 2),
    AppTooltipPlacement.aboveLeft => (rect.top - 6, rect.left),
    AppTooltipPlacement.rightCenter => (rect.top + rect.height / 2, rect.right + 8),
  };
  notifier.show(text: text, top: top, left: left, placement: resolved);
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
    'mouseenter': (event) =>
        showAppTooltipFromEvent(event, notifier, text: text, placement: placement, anchorSelector: anchorSelector),
    'mouseleave': (_) => notifier.hide(),
    'focus': (event) =>
        showAppTooltipFromEvent(event, notifier, text: text, placement: placement, anchorSelector: anchorSelector),
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
      AppTooltipPlacement.belowLeft => null,
      // -100% of the tooltip's OWN height, so it lands above the anchor
      // without anyone having to measure it first.
      AppTooltipPlacement.aboveCenter => 'translate(-50%, -100%)',
      AppTooltipPlacement.aboveLeft => 'translateY(-100%)',
      AppTooltipPlacement.rightCenter => 'translateY(-50%)',
    };

    return span(
      classes: 'app-tooltip${visible ? ' app-tooltip--visible' : ''}',
      attributes: {
        'role': 'tooltip',
        if (visible)
          'style': [
            'top: ${tooltip.top}px',
            'left: ${tooltip.left}px',
            if (transform != null) 'transform: $transform',
          ].join('; '),
      },
      [if (visible) .text(tooltip.text!)],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.app-tooltip').styles(
      padding: .symmetric(horizontal: ZonaiSpacing.s5, vertical: ZonaiSpacing.s3),
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
