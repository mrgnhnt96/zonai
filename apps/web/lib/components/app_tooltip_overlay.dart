import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../constants/theme.dart';
import '../providers/app_tooltip_provider.dart';
import '../utils/app_tooltip_geometry.dart';
import '../constants/spacing.dart';

/// A hidden twin of the tooltip, kept in the document so its box can be
/// measured before the real one renders.
///
/// Placement used to be decided against a hardcoded ~30px height, because the
/// tooltip does not exist until after the state change that shows it -- and a
/// guess is all you can test against. The twin carries the same
/// `.app-tooltip` class, so it inherits the padding, border, font and
/// `max-width` that decide the box, which makes `getBoundingClientRect` on it
/// the real answer rather than an approximation of one.
web.Element? _measureEl;

({double width, double height}) _measureTooltip(String text) {
  final el = _measureEl ??= web.document.createElement('span')
    ..className = 'app-tooltip app-tooltip--measure'
    ..setAttribute('aria-hidden', 'true');

  if (!el.isConnected) {
    web.document.body?.appendChild(el);
  }

  el.textContent = text;
  final rect = el.getBoundingClientRect();
  return (width: rect.width, height: rect.height);
}

void showAppTooltipForElement(
  AppTooltipNotifier notifier, {
  required web.Element anchor,
  required String text,
  AppTooltipPlacement placement = AppTooltipPlacement.belowCenter,
}) {
  final rect = anchor.getBoundingClientRect();
  final size = _measureTooltip(text);

  final position = resolveAppTooltipPosition(
    placement: placement,
    anchorTop: rect.top,
    anchorLeft: rect.left,
    anchorWidth: rect.width,
    anchorHeight: rect.height,
    tooltipWidth: size.width,
    tooltipHeight: size.height,
    viewportWidth: web.window.innerWidth.toDouble(),
    viewportHeight: web.window.innerHeight.toDouble(),
  );

  notifier.show(text: text, top: position.top, left: position.left, placement: position.placement);
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
      // -100% of the tooltip's OWN height, so the placement code can hand
      // over an anchor point and let CSS do the subtraction.
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
        // Tips are authored with hard newlines where the writer wanted a
        // break, so those have to survive -- `nowrap` collapsed them into one
        // unbroken line that ran off the screen. `pre-line` keeps the
        // authored breaks and lets `max-width` wrap whatever is left.
        'white-space': 'pre-line',
        // The `100vw` half is the one that matters on a narrow window: it
        // guarantees the box always fits between the two margins the
        // placement code clamps to, so the clamp can never be asked for the
        // impossible.
        // 16px is two `appTooltipMargin`s, written out because a `const` map
        // cannot interpolate a double.
        'max-width': 'min(24rem, calc(100vw - 16px))',
        'z-index': '400',
        'box-shadow': 'var(--zonai-shadow-sm)',
        'opacity': '0',
        'visibility': 'hidden',
        'transition': 'opacity 0.15s ease, visibility 0.15s ease',
      },
    ),
    css('.app-tooltip--visible').styles(raw: const {'opacity': '1', 'visibility': 'visible'}),
    // The measuring twin. `visibility: hidden` is inherited from
    // `.app-tooltip` and still produces layout, which is the whole point;
    // parking it off-screen keeps it from ever painting or extending the
    // scroll area.
    css('.app-tooltip--measure').styles(raw: const {'left': '-9999px', 'top': '0', 'transition': 'none'}),
  ];
}
