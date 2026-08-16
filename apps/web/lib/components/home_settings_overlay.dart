import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import '../constants/button_sizes.dart';
import '../constants/theme.dart';
import '../providers/home_ui_provider.dart';
import '../providers/session_user_provider.dart';
import 'app_tooltip_overlay.dart';
import 'theme/theme_components.dart';
import 'theme_toggle.dart';
import '../constants/spacing.dart';

const _overlayDuration = Duration(milliseconds: 220);
const _sheetDuration = Duration(milliseconds: 250);

/// Settings dialog rendered outside the sidebar to avoid overflow clipping.
class HomeSettingsOverlay extends StatefulComponent {
  const HomeSettingsOverlay({super.key});

  @override
  State<HomeSettingsOverlay> createState() => _HomeSettingsOverlayState();

  @css
  static List<StyleRule> get styles => [
    css('.home-settings-backdrop').styles(
      position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
      opacity: 0,
      transition: Transition('opacity', duration: _overlayDuration, curve: Curve.easeOut),
      raw: const {'z-index': '200', 'background-color': 'rgb(15 23 42 / 0.45)', 'pointer-events': 'none'},
    ),
    css('.home-settings-backdrop.home-settings--open').styles(opacity: 1, raw: const {'pointer-events': 'auto'}),
    css('.home-settings-panel').styles(
      backgroundColor: surfaceColor,
      border: .all(color: borderColor, width: 1.px, style: .solid),
      padding: .all(ZonaiSpacing.s10),
      display: .flex,
      flexDirection: FlexDirection.column,
      gap: Gap.all(ZonaiSpacing.s8),
      width: 280.px,
      radius: .all(Radius.circular(12.px)),
      opacity: 0,
      transform: Transform.translate(y: ZonaiSpacing.s4),
      transition: Transition.combine([
        Transition('opacity', duration: _overlayDuration, curve: Curve.easeOut),
        Transition('transform', duration: _overlayDuration, curve: Curve.easeOut),
      ]),
      raw: const {'position': 'fixed', 'z-index': '201', 'box-shadow': 'var(--zonai-shadow)'},
    ),
    css('.home-settings-panel.home-settings--open').styles(opacity: 1, transform: Transform.none),
    css('.home-settings-panel--expanded-sidebar').styles(
      raw: const {
        'left': 'calc(260px + 12px)',
        'bottom': '24px',
        'transition': 'left 0.2s ease, opacity 0.22s ease-out, transform 0.22s ease-out',
      },
    ),
    css('.home-settings-panel--collapsed-sidebar').styles(
      raw: const {
        'left': 'calc(52px + 12px)',
        'bottom': '24px',
        'transition': 'left 0.2s ease, opacity 0.22s ease-out, transform 0.22s ease-out',
      },
    ),
    css('.home-settings-panel-header').styles(
      display: .flex,
      flexDirection: FlexDirection.row,
      alignItems: .center,
      justifyContent: .spaceBetween,
      gap: Gap.all(ZonaiSpacing.s6),
    ),
    css('.home-settings-panel-title').styles(margin: .zero, fontSize: 1.rem, fontWeight: .w600),
    css('.home-settings-profile').styles(
      display: .flex,
      flexDirection: FlexDirection.row,
      alignItems: .center,
      gap: Gap.all(ZonaiSpacing.s6),
      padding: .all(ZonaiSpacing.s6),
      radius: .all(Radius.circular(12.px)),
      backgroundColor: bgColor,
    ),
    css(
      '.home-settings-actions',
    ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s4)),
    css('.home-settings-action-row').styles(
      display: .flex,
      flexDirection: FlexDirection.row,
      alignItems: .center,
      justifyContent: .spaceBetween,
      gap: Gap.all(ZonaiSpacing.s6),
      padding: .symmetric(horizontal: ZonaiSpacing.s2, vertical: ZonaiSpacing.s2),
    ),
    css('.home-settings-action-label').styles(fontSize: 0.875.rem, fontWeight: .w500, color: fgColor),
    css('.home-sidebar-avatar').styles(
      width: 32.px,
      height: 32.px,
      flex: Flex(grow: 0, shrink: 0),
      display: .flex,
      alignItems: .center,
      justifyContent: .center,
      radius: .all(Radius.circular(8.px)),
      backgroundColor: selectedBgColor,
      color: primaryColor,
      fontSize: 0.875.rem,
      fontWeight: .w700,
    ),
    css(
      '.home-sidebar-profile-text',
    ).styles(minWidth: .zero, overflow: Overflow.hidden, flex: Flex(grow: 1, shrink: 1)),
    css('.home-sidebar-email').styles(
      display: .block,
      fontSize: 0.8125.rem,
      fontWeight: .w600,
      overflow: Overflow.hidden,
      raw: const {'text-overflow': 'ellipsis', 'white-space': 'nowrap'},
    ),
    css('.home-sidebar-badge').styles(
      display: .inlineBlock,
      margin: .only(top: ZonaiSpacing.s1),
      padding: .symmetric(horizontal: ZonaiSpacing.s3, vertical: ZonaiSpacing.s1),
      radius: .all(Radius.circular(4.px)),
      fontSize: 0.625.rem,
      fontWeight: .w600,
      letterSpacing: 0.04.rem,
      textTransform: .upperCase,
      backgroundColor: selectedBgColor,
      color: primaryColor,
    ),
    css.media(MediaQuery.all(maxWidth: 640.px), [
      css('.home-settings-panel').styles(
        width: .unset,
        radius: BorderRadius.only(topLeft: Radius.circular(16.px), topRight: Radius.circular(16.px)),
        padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s11),
        transform: Transform.translate(y: 100.percent),
        transition: Transition.combine([
          Transition('opacity', duration: _sheetDuration, curve: Curve.easeOut),
          Transition('transform', duration: _sheetDuration, curve: Curve.easeOut),
        ]),
        raw: const {'left': '12px', 'right': '12px', 'bottom': '12px', 'max-height': '85vh', 'overflow-y': 'auto'},
      ),
      css('.home-settings-panel.home-settings--open').styles(transform: Transform.none),
    ]),
  ];
}

class _HomeSettingsOverlayState extends State<HomeSettingsOverlay> {
  bool _render = false;
  bool _open = false;
  bool? _lastSettingsOpen;
  Timer? _unmountTimer;
  Timer? _openTimer;

  @override
  void dispose() {
    _unmountTimer?.cancel();
    _openTimer?.cancel();
    super.dispose();
  }

  void _onOpen() {
    _unmountTimer?.cancel();
    _openTimer?.cancel();
    setState(() {
      _render = true;
      _open = false;
    });
    // Defer --open until after the closed state has been painted; microtasks run
    // in the same frame and the browser skips the enter transition.
    _openTimer = Timer(const Duration(milliseconds: 20), () {
      if (mounted) setState(() => _open = true);
    });
  }

  void _onClose() {
    if (!_render) return;
    _openTimer?.cancel();
    setState(() => _open = false);
    _unmountTimer?.cancel();
    _unmountTimer = Timer(_overlayDuration, () {
      if (mounted) setState(() => _render = false);
    });
  }

  void _syncOpenState(bool settingsOpen) {
    if (_lastSettingsOpen == settingsOpen) return;
    final wasOpen = _lastSettingsOpen == true;
    _lastSettingsOpen = settingsOpen;
    if (settingsOpen) {
      scheduleMicrotask(_onOpen);
    } else if (wasOpen) {
      scheduleMicrotask(_onClose);
    }
  }

  @override
  Component build(BuildContext context) {
    if (!context.binding.isClient) {
      return Component.empty();
    }

    final ui = context.watch(homeUiProvider);
    _syncOpenState(ui.settingsOpen);
    if (!_render) {
      return Component.empty();
    }

    final collapsed = ui.sidebarVisuallyCollapsed;
    final sessionUser = context.watch(sessionUserProvider);
    final label = sessionUser?.label ?? 'Account';
    final initial = sessionUser?.initial ?? '?';
    void close() => context.read(homeUiProvider.notifier).closeSettings();

    final openClass = _open ? ' home-settings--open' : '';
    final panelClass = collapsed
        ? 'home-settings-panel home-settings-panel--collapsed-sidebar$openClass'
        : 'home-settings-panel home-settings-panel--expanded-sidebar$openClass';

    return Component.fragment([
      div(
        classes: 'home-settings-backdrop$openClass',
        attributes: {'aria-hidden': 'true'},
        events: {'click': (_) => close()},
        [],
      ),
      div(
        classes: panelClass,
        attributes: {'role': 'dialog', 'aria-label': 'Account and settings'},
        events: {'click': (event) => event.stopPropagation()},
        [
          div(classes: 'home-settings-panel-header', [
            h2(classes: 'home-settings-panel-title', [.text('Settings')]),
            ZonaiIconButton(
              size: ZonaiIconButtonSize.sm,
              variant: ZonaiIconButtonVariant.ghost,
              attributes: {'aria-label': 'Close settings'},
              onClick: close,
              child: .text('×'),
            ),
          ]),
          div(classes: 'home-settings-profile', [
            div(classes: 'home-sidebar-avatar', [.text(initial)]),
            div(classes: 'home-sidebar-profile-text', [
              span(classes: 'home-sidebar-email', events: appTooltipEvents(context, text: label), [.text(label)]),
              if (sessionUser?.isAdmin == true) span(classes: 'home-sidebar-badge', [.text('Admin')]),
            ]),
          ]),
          div(classes: 'home-settings-actions', [
            div(classes: 'home-settings-action-row', [
              span(classes: 'home-settings-action-label', [.text('Appearance')]),
              const ThemeToggle(),
            ]),
            // The Admins screen hangs off the account panel rather than the
            // table sidebar because it is not a table: it manages who may sign
            // in at all. Shown only to an admin session, which is also the only
            // kind `GET /admin/members` answers — offering it to anyone else
            // would be a link to a 403.
            if (sessionUser?.isAdmin == true)
              ZonaiButton(
                variant: ZonaiButtonVariant.secondary,
                fullWidth: true,
                onClick: () {
                  close();
                  context.goApp(AuthRoutes.admins);
                },
                child: .text('Admins'),
              ),
            ZonaiButton(
              variant: ZonaiButtonVariant.secondary,
              fullWidth: true,
              onClick: () {
                close();
                context.read(authProvider.notifier).signOut();
              },
              child: .text('Sign out'),
            ),
          ]),
        ],
      ),
    ]);
  }
}
