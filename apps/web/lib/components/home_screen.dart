import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import 'theme_toggle.dart';
import '../constants/theme.dart';
import '../providers/table_focus_provider.dart';
import '../providers/table_rows_provider.dart';
import '../providers/sqlite_tables_provider.dart';

class HomeScreen extends StatelessComponent {
  const HomeScreen({super.key});

  @override
  Component build(BuildContext context) {
    final path = context.watch(authRouteProvider);
    final tables = context.watch(sqliteTablesProvider);
    final focused = resolveTableFocus(path, tables);
    // Async providers must not notify after SSR completes (no frames on the server).
    final rowsAsync = context.binding.isClient
        ? context.watch(tableRowsProvider)
        : const AsyncValue<TableRowsData?>.data(null);

    return main_(classes: 'home', [
      aside(classes: 'tables-pane', [
        div(classes: 'tables-pane-header', [.text('Tables')]),
        if (tables.loadError case final error?)
          div(classes: 'tables-pane-error', [
            p(classes: 'tables-pane-msg', [.text('Could not load tables.')]),
            pre(classes: 'tables-pane-err-detail', [.text(error)]),
          ])
        else if (tables.tables.isEmpty)
          p(classes: 'tables-pane-msg', [.text('No tables yet.')])
        else
          ul(classes: 'tables-list', [
            for (final c in tables.tables)
              li(
                classes: 'tables-item${focused == c ? ' tables-item-focused' : ''}',
                [
                  button(
                    [.text(c.displayName)],
                    type: .button,
                    classes: 'tables-item-button',
                    onClick: () {
                      context.read(tableFocusProvider.notifier).setFocused(c);
                    },
                  ),
                ],
              ),
          ]),
      ]),
      div(classes: 'home-main', [
        div(classes: 'home-main-inner', [
          div(classes: 'home-toolbar', [
            const ThemeToggle(),
            button(
              classes: 'sign-out',
              type: .button,
              onClick: () {
                context.read(authProvider.notifier).signOut();
              },
              [.text('Sign out')],
            ),
          ]),
          _TableMain(focused: focused, rowsAsync: rowsAsync),
        ]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
        css('.home', [
          css('&').styles(
            flex: Flex(grow: 1, shrink: 0),
            display: .flex,
            flexDirection: FlexDirection.row,
            alignItems: .stretch,
            minHeight: 100.vh,
            width: 100.percent,
          ),
          css('.tables-pane').styles(
            width: 260.px,
            flex: Flex(grow: 0, shrink: 0),
            backgroundColor: surfaceColor,
            border: Border.only(
              right: BorderSide.solid(color: borderColor, width: 1.px),
            ),
            padding: .symmetric(horizontal: 16.px, vertical: 20.px),
            display: .flex,
            flexDirection: FlexDirection.column,
            gap: Gap.all(12.px),
          ),
          css('.tables-pane-header').styles(
            fontSize: 0.75.rem,
            fontWeight: .w600,
            letterSpacing: 0.04.rem,
            color: mutedColor,
            textTransform: .upperCase,
          ),
          css('.tables-pane-msg').styles(fontSize: 0.875.rem, color: mutedColor),
          css('.tables-pane-error').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(8.px)),
          css('.tables-pane-err-detail').styles(
            fontSize: 0.75.rem,
            color: errorColor,
            margin: .zero,
            raw: const {
              'overflow-wrap': 'anywhere',
              'white-space': 'pre-wrap',
              'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
            },
          ),
          css('.tables-list').styles(
            margin: .zero,
            padding: .zero,
            listStyle: .none,
            overflow: Overflow.auto,
            flex: Flex(grow: 1, shrink: 1),
          ),
          css('.tables-item').styles(
            margin: .only(bottom: 4.px),
            fontSize: 0.875.rem,
            fontWeight: .w500,
          ),
          css('.tables-item-button').styles(
            cursor: .pointer,
            display: .block,
            width: 100.percent,
            textAlign: .left,
            padding: .symmetric(horizontal: 10.px, vertical: 8.px),
            radius: .all(Radius.circular(8.px)),
            backgroundColor: Colors.transparent,
            border: Border.none,
            fontWeight: .w500,
            fontSize: 0.875.rem,
            raw: const {'font': 'inherit'},
          ),
          css('.tables-item:hover .tables-item-button').styles(
            backgroundColor: hoverColor,
          ),
          css('.tables-item-focused .tables-item-button').styles(
            backgroundColor: selectedBgColor,
            color: primaryColor,
            fontWeight: .w600,
          ),
          css('.home-main').styles(
            flex: Flex(grow: 1, shrink: 1),
            display: .flex,
            flexDirection: FlexDirection.column,
            minHeight: .zero,
            padding: .all(24.px),
            overflow: Overflow.hidden,
          ),
          css('.home-main-inner').styles(
            flex: Flex(grow: 1, shrink: 1),
            display: .flex,
            flexDirection: FlexDirection.column,
            gap: Gap.all(16.px),
            minHeight: .zero,
            overflow: Overflow.hidden,
            maxWidth: 1200.px,
            width: 100.percent,
            raw: const {'margin-left': 'auto', 'margin-right': 'auto'},
          ),
          css('.home-toolbar').styles(
            display: .flex,
            flexDirection: FlexDirection.row,
            gap: Gap.all(8.px),
            raw: const {'justify-content': 'flex-end'},
          ),
          css('.sign-out').styles(
            padding: .symmetric(horizontal: 16.px, vertical: 10.px),
            cursor: .pointer,
            radius: .all(Radius.circular(8.px)),
            border: .all(color: borderColor, width: 1.px, style: .solid),
            fontWeight: .w600,
            fontSize: 0.875.rem,
            color: primaryColor,
            backgroundColor: Colors.transparent,
          ),
          css('.sign-out:hover').styles(backgroundColor: hoverColor),
          css('.table-detail-empty').styles(
            flex: Flex(grow: 1, shrink: 1),
            display: .flex,
            alignItems: .center,
            justifyContent: .center,
            padding: .all(32.px),
            border: .all(color: borderColor, width: 1.px, style: .solid),
            radius: .all(Radius.circular(16.px)),
            backgroundColor: surfaceColor,
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
          css('.table-detail-panel').styles(
            flex: Flex(grow: 1, shrink: 1),
            display: .flex,
            flexDirection: FlexDirection.column,
            gap: Gap.all(12.px),
            minHeight: .zero,
            overflow: Overflow.hidden,
          ),
          css('.table-detail-title').styles(
            margin: .zero,
            fontSize: 1.25.rem,
            fontWeight: .w600,
          ),
          css('.table-rows-wrap').styles(
            flex: Flex(grow: 1, shrink: 1),
            overflow: Overflow.auto,
            border: .all(color: borderColor, width: 1.px, style: .solid),
            radius: .all(Radius.circular(12.px)),
            backgroundColor: surfaceColor,
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
            },
          ),
          css('.table-rows-foot').styles(fontSize: 0.8125.rem, color: mutedColor),
        ]),
      ];
}

class _TableMain extends StatelessComponent {
  const _TableMain({
    required this.focused,
    required this.rowsAsync,
  });

  final SqliteTableRef? focused;
  final AsyncValue<TableRowsData?> rowsAsync;

  @override
  Component build(BuildContext context) {
    if (focused == null) {
      return div(classes: 'table-detail-empty', [
        p(classes: 'table-detail-empty-msg', [.text('Select a table to view its rows.')]),
      ]);
    }

    final title = focused!.displayName;
    final children = <Component>[
      h1(classes: 'table-detail-title', [.text(title)]),
    ];

    switch (rowsAsync) {
      case AsyncError(:final error):
        children.add(
          div(classes: 'table-detail-error', [
            p(classes: 'table-detail-error-title', [.text('Could not load rows')]),
            pre(classes: 'table-detail-error-detail', [.text(_errorText(error))]),
          ]),
        );
      case AsyncLoading():
        if (context.binding.isClient) {
          children.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('Loading rows…')]),
            ]),
          );
        } else {
          children.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('Rows load in the browser after sign-in.')]),
            ]),
          );
        }
      case AsyncData(:final value):
        final data = value;
        if (data == null) {
          children.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('Rows load in the browser.')]),
            ]),
          );
        } else if (data.rows.isEmpty) {
          children.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('This table has no rows.')]),
            ]),
          );
        } else {
          children.add(div(classes: 'table-rows-wrap', [
            table(classes: 'rows-table', [
              thead([
                tr([for (final col in data.columns) th([.text(col)])]),
              ]),
              tbody([
                for (final row in data.rows)
                  tr([
                    for (final cell in row) td(classes: 'rows-cell', [.text(_formatCell(cell))]),
                  ]),
              ]),
            ]),
          ]));
          if (data.truncated) {
            children.add(p(classes: 'table-rows-foot', [.text('Showing first page only (results truncated).')]));
          }
        }
    }

    return div(classes: 'table-detail-panel', children);
  }

  static String _formatCell(Object? cell) {
    if (cell == null) return '—';
    return '$cell';
  }

  static String _errorText(Object error) {
    return switch (error) {
      StateError(:final message) => message,
      _ => error.toString(),
    };
  }
}
