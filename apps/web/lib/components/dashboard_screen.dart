import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_routes.dart';
import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../providers/home_ui_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../utils/sqlite_table_utils.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'theme/ui_styles.dart';
import 'toast_overlay.dart';

class DashboardScreen extends StatelessComponent {
  const DashboardScreen({super.key});

  @override
  Component build(BuildContext context) {
    final mobileNavOpen = context.watch(homeUiProvider).mobileNavOpen;
    final tables = context.watch(sqliteTablesProvider);
    final userTables = [
      for (final t in tables.tables)
        if (!isSystemSqliteTable(t.sqliteName)) t,
    ];

    return main_(classes: 'home${mobileNavOpen ? ' home--mobile-nav-open' : ''}', [
      HomeSidebar(focused: null),
      div(classes: 'home-main', [
        div(classes: 'dashboard', [
          div(classes: 'dashboard-header', [
            h1(classes: 'dashboard-title', [.text('Dashboard')]),
          ]),
          div(classes: 'dashboard-stats', [
            const _StatCard(label: 'Requests (24h)', value: '—'),
            const _StatCard(label: 'Error Rate', value: '—'),
            const _StatCard(label: 'p95 Response', value: '—'),
            const _StatCard(label: 'Active Sessions', value: '—'),
          ]),
          div(classes: 'dashboard-row', [
            div(classes: 'dashboard-panel dashboard-panel--wide', [
              p(classes: 'dashboard-panel-title', [.text('Requests over time')]),
              div(classes: 'dashboard-panel-placeholder', [.text('Coming soon')]),
            ]),
            div(classes: 'dashboard-panel', [
              p(classes: 'dashboard-panel-title', [.text('Top Errors (24h)')]),
              div(classes: 'dashboard-panel-placeholder', [.text('Coming soon')]),
            ]),
          ]),
          div(classes: 'dashboard-panel', [
            p(classes: 'dashboard-panel-title', [.text('Cron Jobs')]),
            div(classes: 'dashboard-panel-placeholder', [.text('Coming soon')]),
          ]),
          if (userTables.isNotEmpty)
            div(classes: 'dashboard-section', [
              div(classes: 'dashboard-section-header', [
                p(classes: ZonaiClasses.sectionLabel, [.text('Collections')]),
                a(href: AuthRoutes.tables, classes: 'dashboard-section-link', [
                  .text('View all'),
                ]),
              ]),
              div(classes: 'dashboard-tables', [
                for (final table in userTables)
                  a(
                    href: AuthRoutes.forTable(table.sqliteName),
                    classes: 'dashboard-table-card',
                    [
                      span(classes: 'dashboard-table-name', [.text(table.displayName)]),
                      span(classes: 'dashboard-table-meta', [.text('—')]),
                    ],
                  ),
              ]),
            ]),
        ]),
      ]),
      if (mobileNavOpen)
        div(
          classes: 'home-mobile-backdrop',
          attributes: {'aria-hidden': 'true'},
          events: {'click': (_) => context.read(homeUiProvider.notifier).closeMobileNav()},
          [],
        ),
      const HomeSettingsOverlay(),
      if (context.binding.isClient) const ToastOverlay(),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    ...HomeSidebar.styles,
    ...HomeSettingsOverlay.styles,
    ...ToastOverlay.styles,
    css('.home', [
      css('&').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .stretch,
        width: 100.percent,
        minHeight: .zero,
        overflow: Overflow.hidden,
        raw: const {'position': 'relative'},
      ),
      css('.home-main').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        minHeight: .zero,
        minWidth: .zero,
        padding: .all(ZonaiSpacing.s10),
        overflow: Overflow.auto,
      ),
      css('.home-mobile-backdrop').styles(
        display: .block,
        position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
        raw: const {'z-index': '140', 'background-color': 'rgb(15 23 42 / 0.45)'},
      ),
      css.media(MediaQuery.all(maxWidth: 640.px), [
        css('&').styles(overflow: Overflow.visible),
      ]),
    ]),
    css('.dashboard', [
      css('&').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s10),
        width: 100.percent,
        maxWidth: 1200.px,
      ),
      css('.dashboard-header').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
      ),
      css('.dashboard-title').styles(
        margin: .zero,
        fontSize: 1.375.rem,
        fontWeight: .w600,
        raw: const {'letter-spacing': '-0.02em'},
      ),
      css('.dashboard-stats').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        flexWrap: .wrap,
        gap: Gap.all(ZonaiSpacing.s5),
      ),
      css('.dashboard-stat-card').styles(
        flex: Flex(grow: 1, shrink: 0),
        minWidth: 140.px,
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s2),
        padding: .all(ZonaiSpacing.s8),
        backgroundColor: surfaceColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(12.px)),
        raw: const {'box-shadow': 'var(--zonai-shadow-sm)'},
      ),
      css('.dashboard-stat-label').styles(
        fontSize: 0.6875.rem,
        fontWeight: .w600,
        letterSpacing: 0.04.rem,
        textTransform: .upperCase,
        color: mutedColor,
      ),
      css('.dashboard-stat-value').styles(
        fontSize: 1.5.rem,
        fontWeight: .w600,
        color: fgColor,
        raw: const {'letter-spacing': '-0.02em'},
      ),
      css('.dashboard-row').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        flexWrap: .wrap,
        gap: Gap.all(ZonaiSpacing.s5),
      ),
      css('.dashboard-panel').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s6),
        padding: .all(ZonaiSpacing.s8),
        backgroundColor: surfaceColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(12.px)),
        raw: const {'box-shadow': 'var(--zonai-shadow-sm)'},
      ),
      css('.dashboard-panel--wide').styles(flex: Flex(grow: 2, shrink: 1), minWidth: 320.px),
      css('.dashboard-panel-title').styles(
        margin: .zero,
        fontSize: 0.875.rem,
        fontWeight: .w600,
        color: fgColor,
      ),
      css('.dashboard-panel-placeholder').styles(
        flex: Flex(grow: 1, shrink: 0),
        minHeight: 140.px,
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        fontSize: 0.875.rem,
        color: mutedColor,
        radius: .all(Radius.circular(8.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        raw: const {'border-style': 'dashed'},
      ),
      css('.dashboard-section').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s5),
      ),
      css('.dashboard-section-header').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
      ),
      css('.dashboard-section-link').styles(
        fontSize: 0.8125.rem,
        fontWeight: .w600,
        color: primaryColor,
        raw: const {'text-decoration': 'none'},
      ),
      css('.dashboard-section-link:hover').styles(color: primaryHoverColor),
      css('.dashboard-tables').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        flexWrap: .wrap,
        gap: Gap.all(ZonaiSpacing.s4),
      ),
      css('.dashboard-table-card').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s1),
        padding: .symmetric(horizontal: ZonaiSpacing.s7, vertical: ZonaiSpacing.s6),
        backgroundColor: surfaceColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(10.px)),
        minWidth: 140.px,
        raw: const {
          'text-decoration': 'none',
          'box-shadow': 'var(--zonai-shadow-sm)',
          'transition': 'border-color 0.15s ease, background-color 0.15s ease',
        },
      ),
      css('.dashboard-table-card:hover').styles(
        backgroundColor: hoverColor,
        border: .all(color: mutedColor, width: 1.px, style: .solid),
      ),
      css('.dashboard-table-name').styles(
        fontSize: 0.875.rem,
        fontWeight: .w600,
        color: fgColor,
      ),
      css('.dashboard-table-meta').styles(
        fontSize: 0.75.rem,
        color: mutedColor,
      ),
    ]),
  ];
}

class _StatCard extends StatelessComponent {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Component build(BuildContext context) {
    return div(classes: 'dashboard-stat-card', [
      span(classes: 'dashboard-stat-label', [.text(label)]),
      span(classes: 'dashboard-stat-value', [.text(value)]),
    ]);
  }
}
