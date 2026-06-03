import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../constants/theme.dart';
import '../providers/home_ui_provider.dart';
import '../providers/table_focus_provider.dart';
import '../providers/table_rows_provider.dart';
import '../providers/table_schema_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../auth/auth_route_provider.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'theme/ui_styles.dart';

class HomeScreen extends StatelessComponent {
  const HomeScreen({super.key});

  @override
  Component build(BuildContext context) {
    final path = context.watch(authRouteProvider);
    final tables = context.watch(sqliteTablesProvider);
    final focused = resolveTableFocus(path, tables);
    final mobileNavOpen = context.watch(homeUiProvider).mobileNavOpen;
    // Async providers must not notify after SSR completes (no frames on the server).
    final rowsAsync = context.binding.isClient
        ? context.watch(tableRowsProvider)
        : const AsyncValue<TableRowsData?>.data(null);

    return main_(classes: 'home${mobileNavOpen ? ' home--mobile-nav-open' : ''}', [
      HomeSidebar(focused: focused),
      div(classes: 'home-main', [
        _MobileNavHeader(focused: focused),
        _TableMain(focused: focused, rowsAsync: rowsAsync),
      ]),
      if (mobileNavOpen)
        div(
          classes: 'home-mobile-backdrop',
          attributes: {'aria-hidden': 'true'},
          events: {
            'click': (_) => context.read(homeUiProvider.notifier).closeMobileNav(),
          },
          [],
        ),
      const HomeSettingsOverlay(),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    ...HomeSidebar.styles,
    ...HomeSettingsOverlay.styles,
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
        padding: .all(20.px),
        overflow: Overflow.hidden,
      ),
      css('.home-mobile-nav-header').styles(
        display: .none,
        flex: Flex(grow: 0, shrink: 0),
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(12.px),
        margin: .only(bottom: 16.px),
      ),
      css('.home-mobile-nav-btn').styles(
        width: 40.px,
        height: 40.px,
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        cursor: .pointer,
        radius: .all(Radius.circular(8.px)),
        border: .all(color: borderColor, width: 1.px, style: .solid),
        backgroundColor: surfaceColor,
        color: fgColor,
        fontSize: 1.25.rem,
        padding: .zero,
        flex: Flex(grow: 0, shrink: 0),
        raw: const {'font': 'inherit', 'line-height': '1'},
      ),
      css('.home-mobile-nav-btn:hover').styles(backgroundColor: hoverColor),
      css('.home-mobile-nav-title').styles(
        margin: .zero,
        fontSize: 1.rem,
        fontWeight: .w600,
        overflow: Overflow.hidden,
        raw: const {
          'text-overflow': 'ellipsis',
          'white-space': 'nowrap',
        },
      ),
      css('.home-mobile-backdrop').styles(
        display: .block,
        position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
        raw: const {
          'z-index': '140',
          'background-color': 'rgb(15 23 42 / 0.45)',
        },
      ),
      css.media(
        MediaQuery.all(maxWidth: 640.px),
        [
          css('&').styles(
            overflow: Overflow.visible,
          ),
          css('.home-mobile-nav-header').styles(display: .flex),
        ],
      ),
      css('.table-detail-panel').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(12.px),
        minHeight: .zero,
        overflow: Overflow.hidden,
      ),
      css('.table-detail-header').styles(
        flex: Flex(grow: 0, shrink: 0),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(4.px),
      ),
      css('.table-detail-title').styles(
        margin: .zero,
        fontSize: 1.375.rem,
        fontWeight: .w600,
        raw: const {'letter-spacing': '-0.02em'},
      ),
      css('.table-detail-subtitle').styles(
        margin: .zero,
        fontSize: 0.8125.rem,
        color: mutedColor,
        raw: const {
          'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
        },
      ),
      css('.table-detail-body').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(12.px),
        minHeight: .zero,
        overflow: Overflow.hidden,
      ),
      css('.table-detail-empty').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        padding: .all(32.px),
        minHeight: .zero,
      ),
      css('.table-detail-empty-msg').styles(
        margin: .zero,
        fontSize: 0.95.rem,
        color: mutedColor,
        textAlign: .center,
      ),
      css('.table-detail-error').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(12.px),
        padding: .all(20.px),
        border: .all(color: errorBorderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(12.px)),
        backgroundColor: errorBgColor,
        overflow: Overflow.auto,
        minHeight: .zero,
      ),
      css('.table-detail-error-title').styles(
        margin: .zero,
        fontSize: 0.95.rem,
        fontWeight: .w600,
        color: errorColor,
      ),
      css('.table-detail-error-detail').styles(
        margin: .zero,
        fontSize: 0.8125.rem,
        color: errorFgColor,
        raw: const {
          'white-space': 'pre-wrap',
          'overflow-wrap': 'anywhere',
          'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
        },
      ),
      css('.table-rows-wrap').styles(
        flex: Flex(grow: 1, shrink: 1),
        overflow: Overflow.auto,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(12.px)),
        backgroundColor: surfaceColor,
        minHeight: .zero,
      ),
      css('.rows-table').styles(
        width: 100.percent,
        fontSize: 0.8125.rem,
        raw: const {'border-collapse': 'collapse'},
      ),
      css('.rows-table th').styles(
        backgroundColor: tableHeaderBgColor,
        textAlign: .left,
        padding: .symmetric(horizontal: 12.px, vertical: 10.px),
        fontWeight: .w600,
        raw: const {
          'position': 'sticky',
          'top': '0',
          'border-bottom': '1px solid var(--zonai-border)',
          'white-space': 'nowrap',
        },
      ),
      css('.rows-table td').styles(
        padding: .symmetric(horizontal: 12.px, vertical: 8.px),
        raw: const {
          'border-bottom': '1px solid var(--zonai-border)',
          'vertical-align': 'top',
          'max-width': '320px',
          'white-space': 'pre-wrap',
          'overflow-wrap': 'anywhere',
        },
      ),
      css('.table-rows-foot').styles(fontSize: 0.8125.rem, color: mutedColor, margin: .zero),
    ]),
  ];
}

class _MobileNavHeader extends StatelessComponent {
  const _MobileNavHeader({required this.focused});

  final SqliteTableRef? focused;

  @override
  Component build(BuildContext context) {
    final title = focused?.displayName ?? 'Tables';

    return div(classes: 'home-mobile-nav-header', [
      button(
        classes: 'home-mobile-nav-btn',
        type: .button,
        attributes: {
          'aria-label': 'Open navigation',
          'aria-expanded': context.watch(homeUiProvider).mobileNavOpen ? 'true' : 'false',
        },
        onClick: () => context.read(homeUiProvider.notifier).toggleMobileNav(),
        [.text('☰')],
      ),
      h1(classes: 'home-mobile-nav-title', [.text(title)]),
    ]);
  }
}

class _TableMain extends StatelessComponent {
  const _TableMain({required this.focused, required this.rowsAsync});

  final SqliteTableRef? focused;
  final AsyncValue<TableRowsData?> rowsAsync;

  @override
  Component build(BuildContext context) {
    if (focused == null) {
      return div(classes: '${ZonaiClasses.panel} ${ZonaiClasses.panelEmpty}', [
        p(classes: 'table-detail-empty-msg', [.text('Select a table to view its rows.')]),
      ]);
    }

    final schema = context.watch(tableSchemaProvider);
    final title = focused!.displayName;
    final subtitleParts = <String>[focused!.sqliteName];
    if (schema != null) {
      subtitleParts.add('${schema.columns.length} columns');
    }

    final bodyChildren = <Component>[];

    switch (rowsAsync) {
      case AsyncError(:final error):
        bodyChildren.add(
          div(classes: 'table-detail-error', [
            p(classes: 'table-detail-error-title', [.text('Could not load rows')]),
            pre(classes: 'table-detail-error-detail', [.text(_errorText(error))]),
          ]),
        );
      case AsyncLoading():
        if (context.binding.isClient) {
          bodyChildren.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('Loading rows…')]),
            ]),
          );
        } else {
          bodyChildren.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('Rows load in the browser after sign-in.')]),
            ]),
          );
        }
      case AsyncData(:final value):
        final data = value;
        if (data == null) {
          bodyChildren.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('Rows load in the browser.')]),
            ]),
          );
        } else if (data.rows.isEmpty) {
          subtitleParts.add('0 rows');
          bodyChildren.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('This table has no rows.')]),
            ]),
          );
        } else {
          subtitleParts.add('${data.rows.length} rows');
          bodyChildren.add(
            div(classes: 'table-rows-wrap', [
              table(classes: 'rows-table', [
                thead([
                  tr([
                    for (final shape in data.columnShapes)
                      th(classes: 'rows-header', [.text(columnShapeHeaderLabel(shape))]),
                  ]),
                ]),
                tbody([
                  for (final row in data.rows)
                    tr([
                      for (var i = 0; i < row.length; i++)
                        td(classes: 'rows-cell', [
                          .text(formatSchemaCell(row[i], data.columnShapes.elementAtOrNull(i))),
                        ]),
                    ]),
                ]),
              ]),
            ]),
          );
          if (data.truncated) {
            bodyChildren.add(
              p(classes: 'table-rows-foot', [.text('Showing first page only (results truncated).')]),
            );
          }
        }
    }

    return div(classes: ZonaiClasses.panel, [
      div(classes: 'table-detail-header', [
        h1(classes: 'table-detail-title', [.text(title)]),
        p(classes: 'table-detail-subtitle', [.text(subtitleParts.join(' · '))]),
      ]),
      div(classes: 'table-detail-body', bodyChildren),
    ]);
  }

  static String _errorText(Object error) {
    return switch (error) {
      StateError(:final message) => message,
      _ => error.toString(),
    };
  }
}
