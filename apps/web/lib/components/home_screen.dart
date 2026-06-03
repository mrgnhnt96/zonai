import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../constants/theme.dart';
import '../providers/home_ui_provider.dart';
import '../providers/table_focus_provider.dart';
import '../providers/table_row_selection_provider.dart';
import '../providers/table_rows_provider.dart';
import '../providers/table_schema_provider.dart';
import '../providers/table_sort_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../providers/toast_provider.dart';
import '../utils/table_row_key.dart';
import '../utils/table_rows_sort.dart';
import '../auth/auth_route_provider.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'toast_overlay.dart';
import 'theme/ui_styles.dart';

const _rowsSelectCheckboxCheckSvg =
    "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'%3E%3Cpath fill='none' stroke='%23fff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' d='M2 6l3 3 5-6'/%3E%3C/svg%3E\")";

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

    final sortTooltip = context.watch(tableSortTooltipProvider);

    return main_(classes: 'home${mobileNavOpen ? ' home--mobile-nav-open' : ''}', [
      HomeSidebar(focused: focused),
      div(classes: 'home-main', [
        _MobileNavHeader(focused: focused),
        _TableMain(focused: focused, rowsAsync: rowsAsync),
      ]),
      if (context.binding.isClient && sortTooltip.text != null)
        span(
          classes: 'rows-sort-tooltip rows-sort-tooltip--visible',
          attributes: {
            'role': 'tooltip',
            'style': 'top: ${sortTooltip.top}px; left: ${sortTooltip.left}px;',
          },
          [.text(sortTooltip.text!)],
        ),
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
        raw: const {'text-overflow': 'ellipsis', 'white-space': 'nowrap'},
      ),
      css('.home-mobile-backdrop').styles(
        display: .block,
        position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
        raw: const {'z-index': '140', 'background-color': 'rgb(15 23 42 / 0.45)'},
      ),
      css.media(MediaQuery.all(maxWidth: 640.px), [
        css('&').styles(overflow: Overflow.visible),
        css('.home-mobile-nav-header').styles(display: .flex),
      ]),
      css('.table-detail-panel').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(12.px),
        minHeight: .zero,
        overflow: Overflow.hidden,
      ),
      css(
        '.table-detail-header',
      ).styles(flex: Flex(grow: 0, shrink: 0), display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(4.px)),
      css(
        '.table-detail-title',
      ).styles(margin: .zero, fontSize: 1.375.rem, fontWeight: .w600, raw: const {'letter-spacing': '-0.02em'}),
      css('.table-detail-subtitle').styles(
        margin: .zero,
        fontSize: 0.8125.rem,
        color: mutedColor,
        raw: const {'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'},
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
      css('.table-detail-empty-msg').styles(margin: .zero, fontSize: 0.95.rem, color: mutedColor, textAlign: .center),
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
      css('.table-detail-error-title').styles(margin: .zero, fontSize: 0.95.rem, fontWeight: .w600, color: errorColor),
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
      css('.table-rows-block').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        minHeight: .zero,
        overflow: Overflow.hidden,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(12.px)),
        backgroundColor: surfaceColor,
        raw: const {'position': 'relative'},
      ),
      css('.table-rows-wrap').styles(flex: Flex(grow: 1, shrink: 1), overflow: Overflow.auto, minHeight: .zero),
      css('.table-rows-wrap--selection-open').styles(padding: .only(bottom: 72.px)),
      css('.rows-table').styles(
        fontSize: 0.8125.rem,
        raw: const {'border-collapse': 'collapse', 'width': 'max-content', 'min-width': '100%'},
      ),
      css('.rows-table th').styles(
        backgroundColor: tableHeaderBgColor,
        textAlign: .left,
        padding: .symmetric(horizontal: 12.px, vertical: 10.px),
        fontWeight: .w600,
        overflow: Overflow.hidden,
        raw: const {
          'position': 'sticky',
          'top': '0',
          'border-bottom': '1px solid var(--zonai-border)',
          'white-space': 'nowrap',
          'max-width': '14rem',
          'text-overflow': 'ellipsis',
        },
      ),
      css('.rows-header').styles(
        cursor: .pointer,
        overflow: Overflow.visible,
        raw: const {'user-select': 'none'},
      ),
      css('.rows-header:hover').styles(backgroundColor: hoverColor),
      css('.rows-table th.rows-header').styles(overflow: Overflow.visible),
      css('.rows-header-inner').styles(
        display: .flex,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: Gap.all(8.px),
        width: 100.percent,
        minWidth: .zero,
      ),
      css('.rows-header-label').styles(
        flex: Flex(grow: 1, shrink: 1),
        minWidth: .zero,
        overflow: Overflow.hidden,
        raw: const {'text-overflow': 'ellipsis'},
      ),
      css('.rows-header-sort-icon').styles(
        flex: Flex(grow: 0, shrink: 0),
        display: .inlineFlex,
        alignItems: .center,
        justifyContent: .center,
        width: 1.25.rem,
        height: 1.25.rem,
        fontSize: 0.625.rem,
        color: mutedColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(5.px)),
        boxSizing: .borderBox,
        raw: const {
          'line-height': '1',
          'background-color': 'color-mix(in srgb, var(--zonai-surface) 72%, var(--zonai-table-header-bg))',
        },
      ),
      css('.rows-header-sort-icon--idle').styles(
        visibility: .hidden,
        raw: const {'pointer-events': 'none'},
      ),
      css('.rows-sort-tooltip').styles(
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
          'z-index': '300',
          'box-shadow': 'var(--zonai-shadow-sm)',
          'transform': 'translateX(-50%)',
          'opacity': '0',
          'visibility': 'hidden',
          'transition': 'opacity 0.15s ease, visibility 0.15s ease',
        },
      ),
      css('.rows-sort-tooltip--visible').styles(raw: const {'opacity': '1', 'visibility': 'visible'}),
      css('.rows-table td').styles(
        padding: .symmetric(horizontal: 12.px, vertical: 8.px),
        overflow: Overflow.hidden,
        raw: const {
          'border-bottom': '1px solid var(--zonai-border)',
          'vertical-align': 'top',
          'max-width': '14rem',
          'text-overflow': 'ellipsis',
          'white-space': 'nowrap',
        },
      ),
      css('.rows-table th.rows-select-header, .rows-table td.rows-select-cell').styles(
        width: 3.rem,
        minWidth: 3.rem,
        maxWidth: 3.rem,
        padding: .zero,
        textAlign: .center,
        overflow: Overflow.visible,
        raw: const {
          'border-bottom': '1px solid var(--zonai-border)',
          'vertical-align': 'middle',
        },
      ),
      css('.rows-table th.rows-select-header').styles(
        backgroundColor: tableHeaderBgColor,
        raw: const {'position': 'sticky', 'top': '0', 'z-index': '1'},
      ),
      css('.rows-select-checkbox-wrap').styles(
        display: .flex,
        alignItems: .start,
        justifyContent: .center,
        width: 100.percent,
        padding: .symmetric(horizontal: 12.px, vertical: 10.px),
        boxSizing: .borderBox,
      ),
      css('.rows-select-checkbox').styles(
        width: 1.0625.rem,
        height: 1.0625.rem,
        margin: .zero,
        flex: Flex(grow: 0, shrink: 0),
        cursor: .pointer,
        radius: .all(Radius.circular(4.px)),
        border: .all(color: borderColor, width: 1.px, style: .solid),
        backgroundColor: surfaceColor,
        raw: const {
          'appearance': 'none',
          '-webkit-appearance': 'none',
          'transition': 'border-color 0.15s ease, background-color 0.15s ease, box-shadow 0.15s ease',
        },
      ),
      css('.rows-select-checkbox:hover').styles(
        border: .all(color: mutedColor, width: 1.px, style: .solid),
      ),
      css('.rows-select-checkbox:focus-visible').styles(
        outline: Outline(style: OutlineStyle.none),
        raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'},
      ),
      css('.rows-select-checkbox:checked').styles(
        backgroundColor: primaryColor,
        border: .all(color: primaryColor, width: 1.px, style: .solid),
        raw: const {
          'background-image': _rowsSelectCheckboxCheckSvg,
          'background-repeat': 'no-repeat',
          'background-position': 'center',
          'background-size': '0.65rem 0.65rem',
        },
      ),
      css('.rows-row--selected td').styles(backgroundColor: selectedBgColor),
      css('.table-rows-selection-float').styles(
        display: .flex,
        justifyContent: .center,
        position: Position.absolute(left: 16.px, right: 16.px, bottom: 16.px),
        pointerEvents: .none,
        raw: const {'z-index': '20'},
      ),
      css('.table-rows-selection-bar').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: Gap.all(12.px),
        width: 100.percent,
        maxWidth: 40.rem,
        padding: .symmetric(horizontal: 16.px, vertical: 12.px),
        radius: .all(Radius.circular(12.px)),
        backgroundColor: tableHeaderBgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        pointerEvents: .auto,
        raw: const {
          'box-shadow': 'var(--zonai-shadow)',
        },
      ),
      css('.table-rows-selection-meta').styles(
        display: .flex,
        flexWrap: FlexWrap.wrap,
        alignItems: .center,
        gap: Gap.all(6.px),
        minWidth: .zero,
        flex: Flex(grow: 1, shrink: 1),
        fontSize: 0.875.rem,
        fontWeight: .w500,
        color: fgColor,
        raw: const {'line-height': '1.4'},
      ),
      css('.table-rows-selection-sep').styles(
        color: mutedColor,
        fontWeight: .w400,
        raw: const {'user-select': 'none'},
      ),
      css('.table-rows-selection-select-all').styles(
        padding: .zero,
        margin: .zero,
        border: Border.none,
        color: mutedColor,
        cursor: .pointer,
        fontSize: 0.875.rem,
        fontWeight: .w500,
        textAlign: .left,
        raw: const {
          'background-color': 'transparent',
          'font': 'inherit',
          'line-height': 'inherit',
        },
      ),
      css('.table-rows-selection-select-all:hover:not(:disabled)').styles(
        color: fgColor,
      ),
      css('.rows-selection-delete').styles(
        color: onPrimaryColor,
        backgroundColor: errorColor,
        border: Border.none,
        fontWeight: .w600,
        raw: const {'box-shadow': '0 1px 2px rgb(0 0 0 / 0.12)'},
      ),
      css('.rows-selection-delete:hover:not(:disabled)').styles(
        backgroundColor: errorColor,
        color: onPrimaryColor,
        border: Border.none,
        raw: const {'filter': 'brightness(0.88)'},
      ),
      css('.rows-selection-delete:disabled').styles(
        opacity: 0.65,
        cursor: .notAllowed,
      ),
      css('.table-rows-foot').styles(
        flex: Flex(grow: 0, shrink: 0),
        margin: .zero,
        padding: .symmetric(horizontal: 12.px, vertical: 6.px),
        fontSize: 0.8125.rem,
        color: mutedColor,
        border: .only(
          top: BorderSide.solid(color: borderColor, width: 1.px),
        ),
        raw: const {'line-height': '1.25'},
      ),
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
          subtitleParts.add('${data.total} rows');
          bodyChildren.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text('This table has no rows.')]),
            ]),
          );
        } else {
          subtitleParts.add('${data.total} rows');
          bodyChildren.add(
            _TableRowsBlock(
              data: data,
              sort: context.watch(tableSortProvider),
            ),
          );
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

class _TableRowsBlock extends StatefulComponent {
  const _TableRowsBlock({required this.data, required this.sort});

  final TableRowsData data;
  final TableSortState? sort;

  @override
  State<_TableRowsBlock> createState() => _TableRowsBlockState();
}

class _TableRowsBlockState extends State<_TableRowsBlock> {
  String? _hoveredSortColumn;

  static const _loadMoreThresholdPx = 200.0;

  void _onTableScroll(web.Event event) {
    _maybeLoadMore(event.currentTarget);
  }

  void _maybeLoadMore([web.EventTarget? scrollTarget]) {
    if (!context.binding.isClient || !mounted) return;

    final data = context.read(tableRowsProvider).value;
    if (data == null || !data.truncated || data.isLoadingMore) return;

    final el = scrollTarget ?? web.document.querySelector('.table-rows-wrap');
    if (el is! web.Element) return;

    if (el.scrollTop + el.clientHeight < el.scrollHeight - _loadMoreThresholdPx) {
      return;
    }

    unawaited(context.read(tableRowsProvider.notifier).loadMore());
  }

  void _scheduleFillViewportCheck() {
    if (!context.binding.isClient) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      _maybeLoadMore();
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleFillViewportCheck();
  }

  void _showSortTooltip(web.Event event, String columnName, String text) {
    if (!context.binding.isClient) return;
    _hoveredSortColumn = columnName;
    _positionSortTooltip(event, text);
  }

  void _positionSortTooltip(web.Event event, String text) {
    final el = event.currentTarget;
    if (el is! web.HTMLElement) return;
    final icon = el.querySelector('.rows-header-sort-icon');
    final anchor = icon is web.HTMLElement ? icon : el;
    final rect = anchor.getBoundingClientRect();
    context.read(tableSortTooltipProvider.notifier).show(
      text: text,
      top: rect.bottom + 6,
      left: rect.left + rect.width / 2,
    );
  }

  void _refreshTooltipForHoveredColumn() {
    final column = _hoveredSortColumn;
    if (column == null || !context.binding.isClient) return;
    final sort = context.read(tableSortProvider);
    if (sort?.columnName != column) {
      context.read(tableSortTooltipProvider.notifier).hide();
      return;
    }
    final text = sort!.ascending ? 'Sorted ascending' : 'Sorted descending';
    final header = web.document.querySelector('[data-sort-column="$column"]');
    if (header is! web.HTMLElement) return;
    final icon = header.querySelector('.rows-header-sort-icon');
    final anchor = icon is web.HTMLElement ? icon : header;
    final rect = anchor.getBoundingClientRect();
    context.read(tableSortTooltipProvider.notifier).show(
      text: text,
      top: rect.bottom + 6,
      left: rect.left + rect.width / 2,
    );
  }

  void _hideSortTooltip(_) {
    _hoveredSortColumn = null;
    context.read(tableSortTooltipProvider.notifier).hide();
  }

  @override
  void didUpdateComponent(covariant _TableRowsBlock oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (_hoveredSortColumn != null && oldComponent.sort != component.sort) {
      // Re-run after reconcile so the header DOM matches the new sort arrow.
      Future.microtask(_refreshTooltipForHoveredColumn);
    }
    if (oldComponent.data.rows.length != component.data.rows.length ||
        oldComponent.data.truncated != component.data.truncated) {
      _scheduleFillViewportCheck();
    }
  }

  @override
  Component build(BuildContext context) {
    final data = component.data;
    final sort = component.sort;
    final selection = context.watch(tableRowSelectionProvider);
    final selectionNotifier = context.read(tableRowSelectionProvider.notifier);
    final sortColumnIndex = sort == null ? -1 : data.columns.indexOf(sort.columnName);
    final displayRows = sortColumnIndex < 0
        ? data.rows
        : sortTableRows(
            rows: data.rows,
            columnIndex: sortColumnIndex,
            shape: data.columnShapes.elementAtOrNull(sortColumnIndex),
            ascending: sort!.ascending,
          );
    final displayKeys = [
      for (final row in displayRows) tableRowKey(row, data.columnShapes),
    ];
    final allDisplaySelected = displayKeys.isNotEmpty && displayKeys.every(selection.isSelected);
    final showSelectAllInToolbar = !selection.coversEntireTable &&
        data.total > data.rows.length &&
        allDisplaySelected;

    return div(classes: 'table-rows-block', [
      div(
        classes: 'table-rows-wrap${!selection.isEmpty ? ' table-rows-wrap--selection-open' : ''}',
        events: {
          'scroll': _onTableScroll,
        },
        [
        table(classes: 'rows-table', [
          thead([
            tr([
              th(classes: 'rows-select-header', [
                div(classes: 'rows-select-checkbox-wrap', [
                  input<bool>(
                    type: InputType.checkbox,
                    classes: 'rows-select-checkbox',
                    checked: allDisplaySelected,
                    attributes: {'aria-label': 'Select all rows on this page'},
                    onChange: (selected) => selectionNotifier.setAll(
                      displayKeys,
                      selected: selected,
                    ),
                  ),
                ]),
              ]),
              for (final shape in data.columnShapes)
                _SortableHeader(
                  shape: shape,
                  sort: sort,
                  onShowSortTooltip: _showSortTooltip,
                  onHideSortTooltip: _hideSortTooltip,
                ),
            ]),
          ]),
          tbody([
            for (var r = 0; r < displayRows.length; r++)
              _SelectableRow(
                rowIndex: r,
                row: displayRows[r],
                rowKey: displayKeys[r],
                pageKeys: displayKeys,
                columnShapes: data.columnShapes,
                selected: selection.isSelected(displayKeys[r]),
                selectionNotifier: selectionNotifier,
              ),
          ]),
        ]),
      ]),
      if (!selection.isEmpty)
        div(classes: 'table-rows-selection-float', [
          _SelectionToolbox(
            data: data,
            selection: selection,
            showSelectAll: showSelectAllInToolbar,
          ),
        ]),
      if (data.isLoadingMore)
        p(classes: 'table-rows-foot', [.text('Loading more rows…')]),
    ]);
  }
}

class _SelectableRow extends StatelessComponent {
  const _SelectableRow({
    required this.rowIndex,
    required this.row,
    required this.rowKey,
    required this.pageKeys,
    required this.columnShapes,
    required this.selected,
    required this.selectionNotifier,
  });

  final int rowIndex;
  final List<Object?> row;
  final String rowKey;
  final List<String> pageKeys;
  final List<ColumnShape> columnShapes;
  final bool selected;
  final TableRowSelectionNotifier selectionNotifier;

  @override
  Component build(BuildContext context) {
    return tr(classes: selected ? 'rows-row--selected' : null, [
      td(classes: 'rows-select-cell', [
        div(classes: 'rows-select-checkbox-wrap', [
          input<bool>(
            type: InputType.checkbox,
            classes: 'rows-select-checkbox',
            checked: selected,
            attributes: {'aria-label': 'Select row'},
            events: {
              'click': selectionNotifier.noteCheckboxClick,
            },
            onChange: (selected) => selectionNotifier.handleRowCheckboxChange(
              index: rowIndex,
              key: rowKey,
              selected: selected,
              pageKeys: pageKeys,
            ),
          ),
        ]),
      ]),
      for (var i = 0; i < row.length; i++)
        td(classes: 'rows-cell', [
          .text(formatSchemaCell(row[i], columnShapes.elementAtOrNull(i))),
        ]),
    ]);
  }
}

class _SelectionToolbox extends StatefulComponent {
  const _SelectionToolbox({
    required this.data,
    required this.selection,
    required this.showSelectAll,
  });

  final TableRowsData data;
  final TableRowSelectionState selection;
  final bool showSelectAll;

  @override
  State<_SelectionToolbox> createState() => _SelectionToolboxState();
}

class _SelectionToolboxState extends State<_SelectionToolbox> {
  var _deleting = false;

  Future<void> _deleteSelected() async {
    if (_deleting) return;
    setState(() => _deleting = true);

    final selection = context.read(tableRowSelectionProvider);
    try {
      await context.read(tableRowsProvider.notifier).deleteSelected(selection);
    } catch (e) {
      if (!mounted) return;
      context.read(toastProvider.notifier).showError(
        switch (e) {
          StateError(:final message) => message,
          _ => e.toString(),
        },
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final data = component.data;
    final selection = component.selection;
    final selectedCount = selection.displayCount(data.total);
    final label = selectedCount == 1 ? '1 row selected' : '$selectedCount rows selected';

    return div(classes: 'table-rows-selection-bar', [
      div(classes: 'table-rows-selection-meta', [
        span([.text(label)]),
        if (component.showSelectAll) ...[
          span(classes: 'table-rows-selection-sep', [.text('·')]),
          button(
            classes: 'table-rows-selection-select-all',
            type: .button,
            disabled: _deleting,
            onClick: () => context.read(tableRowSelectionProvider.notifier).selectEntireTable(),
            [.text('Select all ${data.total} rows')],
          ),
        ],
      ]),
      button(
        classes: '${ZonaiClasses.btn} rows-selection-delete',
        type: .button,
        disabled: _deleting,
        onClick: _deleteSelected,
        [.text(_deleting ? 'Deleting…' : 'Delete selected')],
      ),
    ]);
  }
}

class _SortableHeader extends StatelessComponent {
  const _SortableHeader({
    required this.shape,
    required this.sort,
    this.onShowSortTooltip,
    this.onHideSortTooltip,
  });

  final ColumnShape shape;
  final TableSortState? sort;
  final void Function(web.Event event, String columnName, String tooltipText)? onShowSortTooltip;
  final void Function(web.Event event)? onHideSortTooltip;

  @override
  Component build(BuildContext context) {
    final isActive = sort?.columnName == shape.name;
    final label = columnShapeHeaderLabel(shape);
    final tooltipText = isActive
        ? (sort!.ascending ? 'Sorted ascending' : 'Sorted descending')
        : null;

    return th(
      classes: 'rows-header${isActive ? ' rows-header--active' : ''}',
      attributes: {
        'data-sort-column': shape.name,
        if (isActive) 'aria-sort': sort!.ascending ? 'ascending' : 'descending',
      },
      events: {
        'click': (event) {
          context.read(tableSortProvider.notifier).toggleColumn(shape.name);
          final updated = context.read(tableSortProvider);
          if (updated?.columnName == shape.name && onShowSortTooltip != null) {
            final text = updated!.ascending ? 'Sorted ascending' : 'Sorted descending';
            onShowSortTooltip!(event, shape.name, text);
          } else {
            onHideSortTooltip?.call(event);
          }
        },
        if (tooltipText != null && onShowSortTooltip != null)
          'mouseenter': (event) => onShowSortTooltip!(event, shape.name, tooltipText),
        if (onHideSortTooltip != null) 'mouseleave': onHideSortTooltip!,
      },
      [
        span(classes: 'rows-header-inner', [
          span(classes: 'rows-header-label', [.text(label)]),
          span(
            classes: 'rows-header-sort-icon${isActive ? '' : ' rows-header-sort-icon--idle'}',
            attributes: {if (!isActive) 'aria-hidden': 'true'},
            [
              if (isActive) .text(sort!.ascending ? '↑' : '↓'),
            ],
          ),
        ]),
      ],
    );
  }
}
