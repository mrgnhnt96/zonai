import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../constants/theme.dart';
import '../providers/home_ui_provider.dart';
import '../providers/session_user_provider.dart';
import 'theme/theme_components.dart';
import 'theme_toggle.dart';

/// Settings dialog rendered outside the sidebar to avoid overflow clipping.
class HomeSettingsOverlay extends StatelessComponent {
  const HomeSettingsOverlay({super.key});

  @override
  Component build(BuildContext context) {
    final ui = context.watch(homeUiProvider);
    if (!ui.settingsOpen) {
      return Component.empty();
    }

    final collapsed = ui.sidebarVisuallyCollapsed;
    final sessionUser = context.watch(sessionUserProvider);
    final label = sessionUser?.label ?? 'Account';
    final initial = sessionUser?.initial ?? '?';
    final close = () => context.read(homeUiProvider.notifier).closeSettings();

    final panelClass = collapsed
        ? 'home-settings-panel home-settings-panel--collapsed-sidebar'
        : 'home-settings-panel home-settings-panel--expanded-sidebar';

    return Component.fragment([
      div(
        classes: 'home-settings-backdrop',
        attributes: {'aria-hidden': 'true'},
        events: {
          'click': (_) => close(),
        },
        [],
      ),
      div(
        classes: panelClass,
        attributes: {
          'role': 'dialog',
          'aria-label': 'Account and settings',
        },
        events: {
          'click': (event) => event.stopPropagation(),
        },
        [
          div(classes: 'home-settings-panel-header', [
            h2(classes: 'home-settings-panel-title', [.text('Settings')]),
            button(
              classes: 'home-settings-panel-close',
              type: .button,
              attributes: {'aria-label': 'Close settings'},
              onClick: close,
              [.text('×')],
            ),
          ]),
          div(classes: 'home-settings-profile', [
            div(classes: 'home-sidebar-avatar', [.text(initial)]),
            div(classes: 'home-sidebar-profile-text', [
              span(classes: 'home-sidebar-email', attributes: {'title': label}, [.text(label)]),
              if (sessionUser?.isAdmin == true) span(classes: 'home-sidebar-badge', [.text('Admin')]),
            ]),
          ]),
          div(classes: 'home-settings-actions', [
            div(classes: 'home-settings-action-row', [
              span(classes: 'home-settings-action-label', [.text('Appearance')]),
              const ThemeToggle(),
            ]),
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

  @css
  static List<StyleRule> get styles => [
    css('.home-settings-backdrop').styles(
      position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
      raw: const {
        'z-index': '200',
        'background-color': 'rgb(15 23 42 / 0.45)',
        'animation': 'home-settings-backdrop-in 0.2s ease-out',
      },
    ),
    css('.home-settings-panel').styles(
      backgroundColor: surfaceColor,
      border: .all(color: borderColor, width: 1.px, style: .solid),
      padding: .all(20.px),
      display: .flex,
      flexDirection: FlexDirection.column,
      gap: Gap.all(16.px),
      width: 280.px,
      radius: .all(Radius.circular(12.px)),
      raw: const {
        'position': 'fixed',
        'z-index': '201',
        'box-shadow': 'var(--zonai-shadow)',
        'animation': 'home-settings-panel-in 0.2s ease-out',
      },
    ),
    css('.home-settings-panel--expanded-sidebar').styles(
      raw: const {
        'left': 'calc(260px + 12px)',
        'bottom': '24px',
        'transition': 'left 0.2s ease',
      },
    ),
    css('.home-settings-panel--collapsed-sidebar').styles(
      raw: const {
        'left': 'calc(52px + 12px)',
        'bottom': '24px',
        'transition': 'left 0.2s ease',
      },
    ),
    css('.home-settings-panel-header').styles(
      display: .flex,
      flexDirection: FlexDirection.row,
      alignItems: .center,
      justifyContent: .spaceBetween,
      gap: Gap.all(12.px),
    ),
    css('.home-settings-panel-title').styles(
      margin: .zero,
      fontSize: 1.rem,
      fontWeight: .w600,
    ),
    css('.home-settings-panel-close').styles(
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
      raw: const {'font': 'inherit', 'line-height': '1'},
    ),
    css('.home-settings-panel-close:hover').styles(backgroundColor: hoverColor, color: fgColor),
    css('.home-settings-profile').styles(
      display: .flex,
      flexDirection: FlexDirection.row,
      alignItems: .center,
      gap: Gap.all(12.px),
      padding: .all(12.px),
      radius: .all(Radius.circular(12.px)),
      backgroundColor: bgColor,
    ),
    css('.home-settings-actions').styles(
      display: .flex,
      flexDirection: FlexDirection.column,
      gap: Gap.all(8.px),
    ),
    css('.home-settings-action-row').styles(
      display: .flex,
      flexDirection: FlexDirection.row,
      alignItems: .center,
      justifyContent: .spaceBetween,
      gap: Gap.all(12.px),
      padding: .symmetric(horizontal: 4.px, vertical: 4.px),
    ),
    css('.home-settings-action-label').styles(
      fontSize: 0.875.rem,
      fontWeight: .w500,
      color: fgColor,
    ),
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
    css('.home-sidebar-profile-text').styles(
      minWidth: .zero,
      overflow: Overflow.hidden,
      flex: Flex(grow: 1, shrink: 1),
    ),
    css('.home-sidebar-email').styles(
      display: .block,
      fontSize: 0.8125.rem,
      fontWeight: .w600,
      overflow: Overflow.hidden,
      raw: const {
        'text-overflow': 'ellipsis',
        'white-space': 'nowrap',
      },
    ),
    css('.home-sidebar-badge').styles(
      display: .inlineBlock,
      margin: .only(top: 2.px),
      padding: .symmetric(horizontal: 6.px, vertical: 2.px),
      radius: .all(Radius.circular(4.px)),
      fontSize: 0.625.rem,
      fontWeight: .w600,
      letterSpacing: 0.04.rem,
      textTransform: .upperCase,
      backgroundColor: selectedBgColor,
      color: primaryColor,
    ),
    css.media(
      MediaQuery.all(maxWidth: 640.px),
      [
        css('.home-settings-panel').styles(
          width: .unset,
          radius: BorderRadius.only(
            topLeft: Radius.circular(16.px),
            topRight: Radius.circular(16.px),
          ),
          padding: .symmetric(horizontal: 20.px, vertical: 24.px),
          raw: const {
            'left': '12px',
            'right': '12px',
            'bottom': '12px',
            'animation': 'home-settings-sheet-in 0.25s ease-out',
            'max-height': '85vh',
            'overflow-y': 'auto',
          },
        ),
      ],
    ),
    css('@keyframes home-settings-backdrop-in').styles(
      raw: const {
        'from': '{ opacity: 0; }',
        'to': '{ opacity: 1; }',
      },
    ),
    css('@keyframes home-settings-panel-in').styles(
      raw: const {
        'from': '{ opacity: 0; transform: translateY(8px); }',
        'to': '{ opacity: 1; transform: translateY(0); }',
      },
    ),
    css('@keyframes home-settings-sheet-in').styles(
      raw: const {
        'from': '{ opacity: 0; transform: translateY(100%); }',
        'to': '{ opacity: 1; transform: translateY(0); }',
      },
    ),
  ];
}
