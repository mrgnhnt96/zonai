import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../constants/theme.dart';
import '../providers/app_tooltip_provider.dart';
import '../providers/home_ui_provider.dart';
import '../providers/table_focus_provider.dart';
import '../providers/table_row_detail_provider.dart';
import '../providers/table_row_keyboard_focus_provider.dart';
import '../providers/table_row_selection_provider.dart';
import '../providers/resolved_collection_provider.dart';
import '../providers/session_user_provider.dart';
import '../providers/table_rows_provider.dart';
import '../providers/table_schema_provider.dart';
import '../providers/table_sort_provider.dart';
import '../providers/table_filter_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../providers/toast_provider.dart';
import '../utils/download_text_file.dart';
import '../utils/table_row_edit.dart';
import '../utils/table_row_key.dart';
import '../utils/table_rows_sort.dart';
import '../auth/auth_route_provider.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'app_tooltip_overlay.dart';
import 'syntax_highlighted_code.dart';
import 'table_row_detail_panel.dart';
import 'table_edit/table_edit_datetime_field.dart';
import 'table_edit/table_edit_enum_multi_select.dart';
import 'table_filter_datetime_field.dart';
import 'table_search_panel.dart';
import 'table_search_side_panel.dart';
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
          events: {'click': (_) => context.read(homeUiProvider.notifier).closeMobileNav()},
          [],
        ),
      const HomeSettingsOverlay(),
      if (context.binding.isClient) const HomeKeyboardShortcuts(),
      if (context.binding.isClient) const TableRowDetailPanel(),
      if (context.binding.isClient) const TableSearchSidePanel(),
      if (context.binding.isClient) const ToastOverlay(),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    ...HomeSidebar.styles,
    ...HomeSettingsOverlay.styles,
    ...syntaxHighlightedCodeStyles,
    ...tableRowDetailPanelStyles,
    ...ToastOverlay.styles,
    ...tableSearchPanelStyles,
    ...tableSearchSidePanelStyles,
    ...tableEditEnumMultiSelectStyles,
    ...tableEditDatetimeStyles,
    ...tableFilterDatetimeStyles,
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
      css('.table-rows-wrap').styles(
        flex: Flex(grow: 1, shrink: 1),
        overflow: Overflow.auto,
        minHeight: .zero,
        raw: const {'transition': 'padding-bottom 0.2s ease-out'},
      ),
      css('.table-rows-wrap--selection-open').styles(padding: .only(bottom: 72.px)),
      css('.rows-table').styles(
        fontSize: 0.8125.rem,
        raw: const {
          'border-collapse': 'separate',
          'border-spacing': '0',
          'width': 'max-content',
          'min-width': '100%',
        },
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
      css('.rows-header').styles(cursor: .pointer, overflow: Overflow.visible, raw: const {'user-select': 'none'}),
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
      css('.rows-header-sort-icon--idle').styles(visibility: .hidden, raw: const {'pointer-events': 'none'}),
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
        raw: const {'border-bottom': '1px solid var(--zonai-border)', 'vertical-align': 'middle'},
      ),
      css(
        '.rows-table th.rows-select-header',
      ).styles(backgroundColor: tableHeaderBgColor, raw: const {'position': 'sticky', 'top': '0', 'z-index': '1'}),
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
      css('.rows-row').styles(cursor: .pointer),
      css('.rows-row--selected td').styles(backgroundColor: selectedBgColor),
      css('.rows-row--keyboard-focus').styles(
        raw: const {
          'outline': '2px solid var(--zonai-focus-ring)',
          'outline-offset': '-2px',
        },
      ),
      css('.table-rows-selection-float').styles(
        display: .flex,
        justifyContent: .center,
        position: Position.absolute(left: 16.px, right: 16.px, bottom: 16.px),
        pointerEvents: .none,
        raw: const {
          'z-index': '20',
          'opacity': '0',
          'transform': 'translateY(16px)',
          'transition': 'opacity 0.25s ease-out, transform 0.25s ease-out',
        },
      ),
      css(
        '.table-rows-selection-float--open',
      ).styles(pointerEvents: .none, raw: const {'opacity': '1', 'transform': 'translateY(0)'}),
      css(
        '.table-rows-selection-float:not(.table-rows-selection-float--open) .table-rows-selection-bar',
      ).styles(pointerEvents: .none),
      css('.table-rows-selection-bar').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: Gap.all(10.px),
        width: 100.percent,
        maxWidth: 36.rem,
        padding: .symmetric(horizontal: 12.px, vertical: 8.px),
        radius: .all(Radius.circular(12.px)),
        backgroundColor: tableHeaderBgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        pointerEvents: .auto,
        raw: const {'box-shadow': 'var(--zonai-shadow)'},
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
      css('.table-rows-selection-sep').styles(color: mutedColor, fontWeight: .w400, raw: const {'user-select': 'none'}),
      css('.table-rows-selection-select-all').styles(
        padding: .zero,
        margin: .zero,
        border: Border.none,
        color: mutedColor,
        cursor: .pointer,
        fontSize: 0.875.rem,
        fontWeight: .w500,
        textAlign: .left,
        raw: const {'background-color': 'transparent', 'font': 'inherit', 'line-height': 'inherit'},
      ),
      css('.table-rows-selection-select-all:hover:not(:disabled)').styles(color: fgColor),
      css(
        '.table-rows-selection-actions',
      ).styles(display: .flex, alignItems: .center, gap: Gap.all(6.px), flex: Flex(grow: 0, shrink: 0)),
      css('.table-rows-selection-actions .z-btn + .z-btn').styles(margin: .zero),
      css('.table-rows-selection-actions .z-btn').styles(
        padding: .symmetric(horizontal: 10.px, vertical: 6.px),
        fontSize: 0.8125.rem,
      ),
      css('.rows-selection-icon-btn').styles(
        width: 28.px,
        height: 28.px,
        display: .inlineFlex,
        alignItems: .center,
        justifyContent: .center,
        padding: .zero,
        cursor: .pointer,
        radius: .all(Radius.circular(8.px)),
        border: .all(color: borderColor, width: 1.px, style: .solid),
        backgroundColor: surfaceColor,
        color: mutedColor,
        fontSize: 1.125.rem,
        flex: Flex(grow: 0, shrink: 0),
        raw: const {
          'font': 'inherit',
          'line-height': '1',
          'transition': 'background-color 0.15s ease, color 0.15s ease, border-color 0.15s ease, opacity 0.15s ease',
        },
      ),
      css('.rows-selection-icon-btn:hover:not(:disabled)').styles(
        backgroundColor: hoverColor,
        color: fgColor,
        border: .all(color: mutedColor, width: 1.px, style: .solid),
      ),
      css('.rows-selection-icon-btn:disabled').styles(opacity: 0.55, cursor: .notAllowed),
      css('.rows-selection-delete').styles(
        color: onPrimaryColor,
        backgroundColor: errorColor,
        border: Border.none,
        fontWeight: .w600,
        position: Position.relative(),
        overflow: .hidden,
        minWidth: 4.75.rem,
        raw: const {
          'box-shadow': '0 1px 2px rgb(0 0 0 / 0.12)',
          'touch-action': 'manipulation',
          'user-select': 'none',
          '-webkit-user-select': 'none',
        },
      ),
      css('.rows-selection-delete__progress').styles(
        position: Position.absolute(left: 0.px, top: 0.px, bottom: 0.px),
        width: 100.percent,
        raw: const {
          'transform': 'scaleX(0)',
          'transform-origin': 'left center',
          'background-color': 'color-mix(in srgb, var(--zonai-error) 55%, black)',
          'pointer-events': 'none',
          'z-index': '0',
        },
      ),
      css('.rows-selection-delete__progress--resetting').styles(raw: const {'transition': 'transform 75ms ease'}),
      css('.rows-selection-delete__label').styles(position: Position.relative(), raw: const {'z-index': '1'}),
      css('.rows-selection-delete:disabled').styles(opacity: 0.65, cursor: .notAllowed),
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
    final appliedWhere = context.watch(tableAppliedWhereProvider);
    final title = focused!.displayName;
    final subtitleParts = <String>[];
    if (schema != null) {
      subtitleParts.add('${schema.columns.length} columns');
    }

    final bodyChildren = <Component>[];
    final showSearchToggle = context.binding.isClient &&
        ((schema?.columns.isNotEmpty ?? false) ||
            switch (rowsAsync) {
              AsyncData(:final value) when value != null && value.columnShapes.isNotEmpty => true,
              _ => false,
            });

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
          final filterLine = tableFilterSubtitle(appliedWhere, data, data.columnShapes);
          if (filterLine != null) {
            subtitleParts.add(filterLine);
          } else {
            final s = data.total == 1 ? '' : 's';
            subtitleParts.add('${data.total} row$s');
          }
          final emptyMsg = appliedWhere != null
              ? 'No rows match this filter.'
              : 'This table has no rows.';
          bodyChildren.add(
            div(classes: 'table-detail-empty', [
              p(classes: 'table-detail-empty-msg', [.text(emptyMsg)]),
            ]),
          );
        } else {
          final filterLine = tableFilterSubtitle(appliedWhere, data, data.columnShapes);
          if (filterLine != null) {
            subtitleParts.add(filterLine);
          } else {
            final s = data.total == 1 ? '' : 's';
            subtitleParts.add('${data.total} row$s');
          }
          bodyChildren.add(_TableRowsBlock(data: data, sort: context.watch(tableSortProvider)));
        }
    }

    return div(classes: ZonaiClasses.panel, [
      div(classes: 'table-detail-header', [
        div(classes: 'table-detail-header-top', [
          h1(classes: 'table-detail-title', [.text(title)]),
          if (showSearchToggle) const TableSearchToggle(),
        ]),
        if (subtitleParts.isNotEmpty) p(classes: 'table-detail-subtitle', [.text(subtitleParts.join(' · '))]),
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
  var _hadSelection = false;
  var _selectionBarClosing = false;
  Timer? _selectionBarTimer;

  static const _loadMoreThresholdPx = 200.0;
  static const _selectionBarAnimationMs = 250;

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

  @override
  void dispose() {
    _selectionBarTimer?.cancel();
    super.dispose();
  }

  void _syncSelectionBar(bool hasSelection) {
    if (hasSelection == _hadSelection) return;
    _hadSelection = hasSelection;

    if (hasSelection) {
      _selectionBarTimer?.cancel();
      if (_selectionBarClosing) {
        setState(() => _selectionBarClosing = false);
      }
      return;
    }

    if (_selectionBarClosing) return;
    setState(() => _selectionBarClosing = true);
    _selectionBarTimer?.cancel();
    _selectionBarTimer = Timer(const Duration(milliseconds: _selectionBarAnimationMs), () {
      if (!mounted) return;
      if (context.read(tableRowSelectionProvider).isEmpty) {
        setState(() => _selectionBarClosing = false);
      }
    });
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
    final anchor = icon ?? el;
    showAppTooltipForElement(context.read(appTooltipProvider.notifier), anchor: anchor, text: text);
  }

  void _refreshTooltipForHoveredColumn() {
    final column = _hoveredSortColumn;
    if (column == null || !context.binding.isClient) return;
    final sort = context.read(tableSortProvider);
    if (sort?.columnName != column) {
      context.read(appTooltipProvider.notifier).hide();
      return;
    }
    final text = sort!.ascending ? 'Sorted ascending' : 'Sorted descending';
    final header = web.document.querySelector('[data-sort-column="$column"]');
    if (header == null) return;
    final icon = header.querySelector('.rows-header-sort-icon');
    showAppTooltipForElement(context.read(appTooltipProvider.notifier), anchor: icon ?? header, text: text);
  }

  void _hideSortTooltip(_) {
    _hoveredSortColumn = null;
    context.read(appTooltipProvider.notifier).hide();
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
    final detailKey = context.watch(tableRowDetailProvider)?.rowKey;
    final keyboardFocus = context.watch(tableRowKeyboardFocusProvider);
    final keyboardFocusKey = keyboardFocus.zone == HomeKeyboardFocusZone.tableRows ? keyboardFocus.rowKey : null;
    final detailNotifier = context.read(tableRowDetailProvider.notifier);
    final sortColumnIndex = sort == null ? -1 : data.columns.indexOf(sort.columnName);
    final displayRows = sortColumnIndex < 0
        ? data.rows
        : sortTableRows(
            rows: data.rows,
            columnIndex: sortColumnIndex,
            shape: data.columnShapes.elementAtOrNull(sortColumnIndex),
            ascending: sort!.ascending,
          );
    final displayKeys = [for (final row in displayRows) tableRowKey(row, data.columnShapes)];
    final allDisplaySelected = displayKeys.isNotEmpty && displayKeys.every(selection.isSelected);
    final showSelectAllInToolbar = !selection.coversEntireTable && data.total > data.rows.length && allDisplaySelected;
    final hasSelection = !selection.isEmpty;
    final selectionBarOpen = hasSelection || _selectionBarClosing || (!hasSelection && _hadSelection);
    if (hasSelection != _hadSelection) {
      scheduleMicrotask(() {
        if (mounted) _syncSelectionBar(hasSelection);
      });
    }

    return div(classes: 'table-rows-block', [
      div(
        classes: 'table-rows-wrap${selectionBarOpen ? ' table-rows-wrap--selection-open' : ''}',
        events: {'scroll': _onTableScroll},
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
                      onChange: (selected) => selectionNotifier.setAll(displayKeys, selected: selected),
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
                  sqliteName: data.sqliteName,
                  columns: data.columns,
                  columnShapes: data.columnShapes,
                  selected: selection.isSelected(displayKeys[r]),
                  detailActive: displayKeys[r] == detailKey,
                  keyboardFocused: displayKeys[r] == keyboardFocusKey,
                  selectionNotifier: selectionNotifier,
                  detailNotifier: detailNotifier,
                ),
            ]),
          ]),
        ],
      ),
      div(classes: 'table-rows-selection-float${selectionBarOpen ? ' table-rows-selection-float--open' : ''}', [
        _SelectionToolbox(data: data, selection: selection, showSelectAll: showSelectAllInToolbar),
      ]),
      if (data.isLoadingMore) p(classes: 'table-rows-foot', [.text('Loading more rows…')]),
    ]);
  }
}

class _SelectableRow extends StatelessComponent {
  const _SelectableRow({
    required this.rowIndex,
    required this.row,
    required this.rowKey,
    required this.pageKeys,
    required this.sqliteName,
    required this.columns,
    required this.columnShapes,
    required this.selected,
    required this.detailActive,
    required this.keyboardFocused,
    required this.selectionNotifier,
    required this.detailNotifier,
  });

  final int rowIndex;
  final List<Object?> row;
  final String rowKey;
  final List<String> pageKeys;
  final String sqliteName;
  final List<String> columns;
  final List<ColumnShape> columnShapes;
  final bool selected;
  final bool detailActive;
  final bool keyboardFocused;
  final TableRowSelectionNotifier selectionNotifier;
  final TableRowDetailNotifier detailNotifier;

  String? get _rowClass {
    final parts = <String>['rows-row'];
    if (selected || detailActive) parts.add('rows-row--selected');
    if (keyboardFocused) parts.add('rows-row--keyboard-focus');
    return parts.join(' ');
  }

  @override
  Component build(BuildContext context) {
    return tr(
      classes: _rowClass,
      attributes: {'data-row-key': rowKey},
      events: {
        'click': (_) {
          context.read(tableRowKeyboardFocusProvider.notifier).focusRowKey(
            rowKey,
            tableSqliteName: sqliteName,
          );
          detailNotifier.toggle(
          rowKey: rowKey,
          row: row,
          sqliteName: sqliteName,
          columns: columns,
          columnShapes: columnShapes,
          );
        },
      },
      [
        td(
          classes: 'rows-select-cell',
          events: {'click': (event) => event.stopPropagation()},
          [
            div(classes: 'rows-select-checkbox-wrap', [
              input<bool>(
                type: InputType.checkbox,
                classes: 'rows-select-checkbox',
                checked: selected,
                attributes: {'aria-label': 'Select row'},
                events: {'click': selectionNotifier.noteCheckboxClick},
                onChange: (selected) => selectionNotifier.handleRowCheckboxChange(
                  index: rowIndex,
                  key: rowKey,
                  selected: selected,
                  pageKeys: pageKeys,
                ),
              ),
            ]),
          ],
        ),
        for (var i = 0; i < row.length; i++)
          td(classes: 'rows-cell', [.text(formatSchemaCell(row[i], columnShapes.elementAtOrNull(i)))]),
      ],
    );
  }
}

class _SelectionToolbox extends StatefulComponent {
  const _SelectionToolbox({required this.data, required this.selection, required this.showSelectAll});

  final TableRowsData data;
  final TableRowSelectionState selection;
  final bool showSelectAll;

  @override
  State<_SelectionToolbox> createState() => _SelectionToolboxState();
}

enum _DeleteHoldPhase { idle, holding, resetting }

class _SelectionToolboxState extends State<_SelectionToolbox> {
  static const _deleteHoldDuration = Duration(milliseconds: 2500);
  static const _deleteHoldResetDuration = Duration(milliseconds: 75);

  var _deleting = false;
  var _exporting = false;
  var _deleteHoldPhase = _DeleteHoldPhase.idle;
  var _holdProgress = 0.0;

  Timer? _holdProgressTimer;
  Timer? _deleteHoldResetTimer;
  DateTime? _holdStartedAt;
  web.EventListener? _deleteHoldEndListener;
  var _deleteHoldEndListenersActive = false;

  bool get _busy => _deleting || _exporting;

  bool get _requiresDeleteHold {
    final data = component.data;
    if (data.total <= 0) return false;
    return component.selection.displayCount(data.total) == data.total;
  }

  @override
  void initState() {
    super.initState();
    _deleteHoldEndListener = _onDeleteHoldEnd.toJS;
  }

  @override
  void dispose() {
    _stopHoldProgressAnimation();
    _deleteHoldResetTimer?.cancel();
    _cancelDeleteHold(resetVisual: false);
    super.dispose();
  }

  void _hideTooltip() {
    if (!mounted) return;
    context.read(appTooltipProvider.notifier).hide();
  }

  static double _holdEase(double t) => t * t * (3 - 2 * t);

  void _onDeleteHoldEnd(web.Event _) => _cancelDeleteHold();

  void _bindDeleteHoldEndListener() {
    if (_deleteHoldEndListenersActive) return;
    final listener = _deleteHoldEndListener;
    if (listener == null) return;
    _deleteHoldEndListenersActive = true;
    web.document.addEventListener('pointerup', listener);
    web.document.addEventListener('pointercancel', listener);
    web.document.addEventListener('mouseup', listener);
  }

  void _unbindDeleteHoldEndListener() {
    if (!_deleteHoldEndListenersActive) return;
    final listener = _deleteHoldEndListener;
    if (listener == null) return;
    web.document.removeEventListener('pointerup', listener);
    web.document.removeEventListener('pointercancel', listener);
    web.document.removeEventListener('mouseup', listener);
    _deleteHoldEndListenersActive = false;
  }

  void _stopHoldProgressAnimation() {
    _holdProgressTimer?.cancel();
    _holdProgressTimer = null;
  }

  void _tickDeleteHold() {
    if (!mounted || _deleteHoldPhase != _DeleteHoldPhase.holding || _holdStartedAt == null) return;

    final elapsedMs = DateTime.now().difference(_holdStartedAt!).inMilliseconds;
    final linear = (elapsedMs / _deleteHoldDuration.inMilliseconds).clamp(0.0, 1.0);
    final progress = _holdEase(linear);
    if (linear >= 1.0) {
      _stopHoldProgressAnimation();
      _completeDeleteHold();
      return;
    }
    setState(() => _holdProgress = progress);
  }

  void _startDeleteHold(web.Event event) {
    if (_busy || !_requiresDeleteHold || _deleteHoldPhase != _DeleteHoldPhase.idle) return;
    if (event is web.MouseEvent && event.button != 0) return;
    if (event is web.PointerEvent && event.button != 0) return;
    event.preventDefault();

    _hideTooltip();
    _stopHoldProgressAnimation();
    _holdStartedAt = DateTime.now();
    setState(() {
      _deleteHoldPhase = _DeleteHoldPhase.holding;
      _holdProgress = 0;
    });
    _bindDeleteHoldEndListener();
    _holdProgressTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tickDeleteHold());
  }

  void _blockDeleteClick(web.Event event) {
    if (!_requiresDeleteHold) return;
    event.preventDefault();
    event.stopPropagation();
  }

  void _onDeleteButtonClick() {
    if (_requiresDeleteHold) return;
    _hideTooltip();
    _deleteSelected();
  }

  void _cancelDeleteHold({bool resetVisual = true}) {
    _stopHoldProgressAnimation();
    _holdStartedAt = null;
    _unbindDeleteHoldEndListener();

    if (_deleteHoldPhase != _DeleteHoldPhase.holding) return;

    if (!resetVisual) {
      setState(() {
        _deleteHoldPhase = _DeleteHoldPhase.idle;
        _holdProgress = 0;
      });
      return;
    }

    setState(() {
      _deleteHoldPhase = _DeleteHoldPhase.resetting;
      _holdProgress = 0;
    });
    _deleteHoldResetTimer?.cancel();
    _deleteHoldResetTimer = Timer(_deleteHoldResetDuration, () {
      if (!mounted) return;
      setState(() => _deleteHoldPhase = _DeleteHoldPhase.idle);
    });
  }

  void _completeDeleteHold() {
    if (_deleteHoldPhase != _DeleteHoldPhase.holding) return;
    _stopHoldProgressAnimation();
    _holdStartedAt = null;
    _unbindDeleteHoldEndListener();
    _hideTooltip();
    setState(() {
      _deleteHoldPhase = _DeleteHoldPhase.idle;
      _holdProgress = 1.0;
      _deleting = true;
    });
    _runDeleteSelected();
  }

  Future<void> _exportSelectedAsJson() async {
    if (_busy) return;
    setState(() => _exporting = true);

    final selection = context.read(tableRowSelectionProvider);
    try {
      final json = await context.read(tableRowsProvider.notifier).jsonForSelectedRows(selection);
      final tableName = component.data.sqliteName;
      downloadTextFile(filename: '$tableName-rows.json', content: json, mimeType: 'application/json;charset=utf-8');
    } catch (e) {
      if (!mounted) return;
      context.read(toastProvider.notifier).showError(switch (e) {
        StateError(:final message) => message,
        _ => 'Failed to export rows: $e',
      });
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _deleteSelected({bool holdConfirmed = false}) async {
    if (_busy) return;
    if (_requiresDeleteHold && !holdConfirmed) return;
    _hideTooltip();
    setState(() => _deleting = true);
    await _runDeleteSelected();
  }

  Future<void> _runDeleteSelected() async {
    final selection = context.read(tableRowSelectionProvider);
    try {
      await context.read(tableRowsProvider.notifier).deleteSelected(selection);
    } catch (e) {
      if (!mounted) return;
      context.read(toastProvider.notifier).showError(switch (e) {
        StateError(:final message) => message,
        _ => e.toString(),
      });
    } finally {
      _hideTooltip();
      if (mounted) {
        setState(() {
          _deleting = false;
          if (!context.read(tableRowSelectionProvider).isEmpty) {
            _holdProgress = 0;
          }
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final data = component.data;
    final selection = component.selection;
    final selectedCount = selection.displayCount(data.total);
    final label = selectedCount == 1 ? '1 selected' : '$selectedCount selected';
    final allActions = context.watch(tableCollectionActionsProvider);
    final sessionCanEdit = context.watch(sessionUserProvider)?.canEdit == true;
    final canDeleteRows = canDeleteTableRows(
      allActions: allActions,
      actions: allActions[data.sqliteName],
      sessionCanEdit: sessionCanEdit,
      sqliteName: data.sqliteName,
      columnShapes: data.columnShapes,
    );

    return div(classes: 'table-rows-selection-bar', [
      div(classes: 'table-rows-selection-meta', [
        span([.text(label)]),
        if (component.showSelectAll) ...[
          span(classes: 'table-rows-selection-sep', [.text('·')]),
          button(
            classes: 'table-rows-selection-select-all',
            type: .button,
            disabled: _busy,
            attributes: {'aria-label': 'Select all ${data.total} rows'},
            events: appTooltipEvents(context, text: 'Select all ${data.total} rows'),
            onClick: () => context.read(tableRowSelectionProvider.notifier).selectEntireTable(),
            [.text('All ${data.total}')],
          ),
        ],
      ]),
      div(classes: 'table-rows-selection-actions', [
        button(
          classes: 'rows-selection-icon-btn',
          type: .button,
          disabled: _busy,
          attributes: {'aria-label': _exporting ? 'Exporting rows' : 'Export selected rows as JSON'},
          events: appTooltipEvents(context, text: 'Export JSON'),
          onClick: _exportSelectedAsJson,
          [_selectionExportIcon()],
        ),
        if (canDeleteRows)
          button(
            classes: [
              ZonaiClasses.btn,
              'rows-selection-delete',
              if (_deleteHoldPhase == _DeleteHoldPhase.holding) 'rows-selection-delete--holding',
              if (_deleteHoldPhase == _DeleteHoldPhase.resetting) 'rows-selection-delete--resetting',
            ].join(' '),
            type: .button,
            disabled: _busy,
            attributes: {
              if (_requiresDeleteHold) 'aria-label': 'Hold for 2.5 seconds to delete all rows',
              if (_deleting) 'aria-busy': 'true',
            },
            events: _requiresDeleteHold
                ? {
                    'pointerdown': _startDeleteHold,
                    'mousedown': _startDeleteHold,
                    'click': _blockDeleteClick,
                    ...appTooltipEvents(context, text: 'Hold to delete all rows'),
                  }
                : null,
            onClick: _onDeleteButtonClick,
            [
              if (_requiresDeleteHold)
                div(
                  classes: [
                    'rows-selection-delete__progress',
                    if (_deleteHoldPhase == _DeleteHoldPhase.resetting) 'rows-selection-delete__progress--resetting',
                  ].join(' '),
                  attributes: {'aria-hidden': 'true', 'style': 'transform: scaleX($_holdProgress);'},
                  [],
                ),
              span(classes: 'rows-selection-delete__label', [.text('Delete')]),
            ],
          ),
        button(
          classes: 'rows-selection-icon-btn',
          type: .button,
          disabled: _busy,
          attributes: {'aria-label': 'Deselect rows'},
          events: appTooltipEvents(context, text: 'Deselect'),
          onClick: () => context.read(tableRowSelectionProvider.notifier).clear(),
          [.text('×')],
        ),
      ]),
    ]);
  }
}

Component _selectionExportIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 14.px,
    height: 14.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M8 2.75v6.5M5.75 7.25 8 9.5l2.25-2.25',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M3.5 12.75h9',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
}

class _SortableHeader extends StatelessComponent {
  const _SortableHeader({required this.shape, required this.sort, this.onShowSortTooltip, this.onHideSortTooltip});

  final ColumnShape shape;
  final TableSortState? sort;
  final void Function(web.Event event, String columnName, String tooltipText)? onShowSortTooltip;
  final void Function(web.Event event)? onHideSortTooltip;

  @override
  Component build(BuildContext context) {
    final isActive = sort?.columnName == shape.name;
    final label = columnShapeHeaderLabel(shape);
    final tooltipText = isActive ? (sort!.ascending ? 'Sorted ascending' : 'Sorted descending') : null;

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
            [if (isActive) .text(sort!.ascending ? '↑' : '↓')],
          ),
        ]),
      ],
    );
  }
}

bool _shouldIgnoreHomeKeyboard(web.KeyboardEvent event) {
  if (event.metaKey || event.ctrlKey || event.altKey) return true;
  final target = event.target;
  if (target is! web.HTMLElement) return false;
  final tag = target.tagName.toLowerCase();
  if (tag == 'input' || tag == 'textarea' || tag == 'select') {
    if (tag == 'input' && event.key == 'Escape' && target is web.HTMLInputElement && target.type == 'checkbox') {
      return false;
    }
    return true;
  }
  return target.isContentEditable;
}

bool _isFocusedDomElement(web.Element? element) {
  if (element == null) return false;
  if (element == web.document.body || element == web.document.documentElement) return false;
  return element is web.HTMLElement;
}

bool _hasHomeFocus(BuildContext context) {
  final ui = context.read(homeUiProvider);
  if (ui.settingsOpen || ui.mobileNavOpen) return true;

  if (_isFocusedDomElement(web.document.activeElement)) return true;

  final keyboardFocus = context.read(tableRowKeyboardFocusProvider);
  return keyboardFocus.zone == HomeKeyboardFocusZone.sidebar || keyboardFocus.rowKey != null;
}

void _clearHomeFocus(BuildContext context) {
  final ui = context.read(homeUiProvider);
  final uiNotifier = context.read(homeUiProvider.notifier);
  if (ui.settingsOpen) {
    uiNotifier.closeSettings();
    return;
  }
  if (ui.mobileNavOpen) {
    uiNotifier.closeMobileNav();
    return;
  }

  final active = web.document.activeElement;
  if (active is web.HTMLElement && _isFocusedDomElement(active)) {
    active.blur();
  }

  final keyboardFocus = context.read(tableRowKeyboardFocusProvider);
  if (keyboardFocus.zone == HomeKeyboardFocusZone.sidebar || keyboardFocus.rowKey != null) {
    context.read(tableRowKeyboardFocusProvider.notifier).clear();
  }
}

({List<List<Object?>> rows, List<String> keys}) _displayRowsAndKeys(
  TableRowsData data,
  TableSortState? sort,
) {
  final sortColumnIndex = sort == null ? -1 : data.columns.indexOf(sort.columnName);
  final displayRows = sortColumnIndex < 0
      ? data.rows
      : sortTableRows(
          rows: data.rows,
          columnIndex: sortColumnIndex,
          shape: data.columnShapes.elementAtOrNull(sortColumnIndex),
          ascending: sort!.ascending,
        );
  final displayKeys = [for (final row in displayRows) tableRowKey(row, data.columnShapes)];
  return (rows: displayRows, keys: displayKeys);
}

void _scrollFocusedRowIntoView(String rowKey) {
  final row = web.document.querySelector('[data-row-key="$rowKey"]');
  row?.scrollIntoView(web.ScrollIntoViewOptions(block: 'nearest'));
}

void _openDetailForRowKey({
  required BuildContext context,
  required String rowKey,
  required List<List<Object?>> displayRows,
  required List<String> displayKeys,
  required TableRowsData data,
  required TableRowDetailViewMode viewMode,
  bool viaEditShortcut = false,
}) {
  final index = displayKeys.indexOf(rowKey);
  if (index < 0) return;
  context.read(tableRowDetailProvider.notifier).openFocusedRow(
    rowKey: rowKey,
    row: displayRows[index],
    sqliteName: data.sqliteName,
    columns: data.columns,
    columnShapes: data.columnShapes,
    viewMode: viewMode,
    viaEditShortcut: viaEditShortcut,
  );
}

class HomeKeyboardShortcuts extends StatefulComponent {
  const HomeKeyboardShortcuts({super.key});

  @override
  State<HomeKeyboardShortcuts> createState() => _HomeKeyboardShortcutsState();
}

class _HomeKeyboardShortcutsState extends State<HomeKeyboardShortcuts> {
  web.EventListener? _keyListener;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_bindKeyListener);
  }

  @override
  void dispose() {
    _unbindKeyListener();
    super.dispose();
  }

  void _bindKeyListener() {
    if (_keyListener != null || !context.binding.isClient) return;
    _keyListener = _onKeyDown.toJS;
    web.document.addEventListener('keydown', _keyListener);
  }

  void _unbindKeyListener() {
    final listener = _keyListener;
    if (listener == null) return;
    web.document.removeEventListener('keydown', listener);
    _keyListener = null;
  }

  void _onKeyDown(web.Event event) {
    if (event is! web.KeyboardEvent) return;
    if (!mounted) return;
    if (_shouldIgnoreHomeKeyboard(event)) return;

    final detail = context.read(tableRowDetailProvider);
    if (detail?.viewMode == TableRowDetailViewMode.edit) return;

    final focusNotifier = context.read(tableRowKeyboardFocusProvider.notifier);
    final keyboardFocus = context.read(tableRowKeyboardFocusProvider);
    final zone = keyboardFocus.zone;
    final tableFocus = context.read(tableFocusProvider);
    final sort = context.read(tableSortProvider);
    final data = context.read(tableRowsProvider).value;

    switch (event.key) {
      case 'ArrowLeft':
        if (zone != HomeKeyboardFocusZone.tableRows || tableFocus == null) return;
        event.preventDefault();
        focusNotifier.enterSidebar(
          tableSqliteName: tableFocus.sqliteName,
          currentRowKey: keyboardFocus.rowKey,
        );
        return;
      case 'ArrowRight':
        if (zone != HomeKeyboardFocusZone.sidebar || tableFocus == null) return;
        event.preventDefault();
        final pageKeys = data == null ? <String>[] : _displayRowsAndKeys(data, sort).keys;
        focusNotifier.exitToTableRows(
          tableSqliteName: tableFocus.sqliteName,
          pageKeys: pageKeys,
        );
        final rowKey = context.read(tableRowKeyboardFocusProvider).rowKey;
        if (rowKey != null) _scrollFocusedRowIntoView(rowKey);
        return;
      case 'ArrowUp':
        if (zone == HomeKeyboardFocusZone.sidebar) {
          event.preventDefault();
          focusNotifier.moveSidebarTableBy(-1);
          return;
        }
      case 'ArrowDown':
        if (zone == HomeKeyboardFocusZone.sidebar) {
          event.preventDefault();
          focusNotifier.moveSidebarTableBy(1);
          return;
        }
      case ' ':
      case 'Enter':
        if (zone == HomeKeyboardFocusZone.sidebar) {
          if (keyboardFocus.sidebarTableSqliteName == null) return;
          event.preventDefault();
          focusNotifier.selectSidebarTable(context);
          return;
        }
      default:
        if (zone == HomeKeyboardFocusZone.sidebar) return;
    }

    if (data == null || data.rows.isEmpty) return;

    final displayed = _displayRowsAndKeys(data, sort);
    final displayRows = displayed.rows;
    final displayKeys = displayed.keys;
    final focusKey = keyboardFocus.rowKey;
    final selectionNotifier = context.read(tableRowSelectionProvider.notifier);
    final detailNotifier = context.read(tableRowDetailProvider.notifier);
    final activeKey = focusKey ?? detail?.rowKey;
    final tableSqliteName = data.sqliteName;

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        focusNotifier.moveBy(1, displayKeys, tableSqliteName: tableSqliteName);
        final nextKey = context.read(tableRowKeyboardFocusProvider).rowKey;
        if (nextKey != null) {
          _scrollFocusedRowIntoView(nextKey);
          if (detail != null) {
            _openDetailForRowKey(
              context: context,
              rowKey: nextKey,
              displayRows: displayRows,
              displayKeys: displayKeys,
              data: data,
              viewMode: detail.viewMode,
            );
          }
        }
      case 'ArrowUp':
        event.preventDefault();
        focusNotifier.moveBy(-1, displayKeys, tableSqliteName: tableSqliteName);
        final nextKey = context.read(tableRowKeyboardFocusProvider).rowKey;
        if (nextKey != null) {
          _scrollFocusedRowIntoView(nextKey);
          if (detail != null) {
            _openDetailForRowKey(
              context: context,
              rowKey: nextKey,
              displayRows: displayRows,
              displayKeys: displayKeys,
              data: data,
              viewMode: detail.viewMode,
            );
          }
        }
      case ' ':
        if (activeKey == null) return;
        event.preventDefault();
        final index = displayKeys.indexOf(activeKey);
        if (index < 0) return;
        final selected = context.read(tableRowSelectionProvider).isSelected(activeKey);
        selectionNotifier.handleRowCheckboxChange(
          index: index,
          key: activeKey,
          selected: !selected,
          pageKeys: displayKeys,
          shiftKey: event.shiftKey,
        );
      case 'Enter':
        if (activeKey == null) return;
        event.preventDefault();
        _openDetailForRowKey(
          context: context,
          rowKey: activeKey,
          displayRows: displayRows,
          displayKeys: displayKeys,
          data: data,
          viewMode: TableRowDetailViewMode.fields,
        );
      case 'j':
      case 'J':
        if (activeKey == null) return;
        event.preventDefault();
        _openDetailForRowKey(
          context: context,
          rowKey: activeKey,
          displayRows: displayRows,
          displayKeys: displayKeys,
          data: data,
          viewMode: TableRowDetailViewMode.json,
        );
      case 'f':
      case 'F':
        if (activeKey == null) return;
        event.preventDefault();
        if (detail?.rowKey == activeKey) {
          detailNotifier.setViewMode(TableRowDetailViewMode.fields);
        } else {
          _openDetailForRowKey(
            context: context,
            rowKey: activeKey,
            displayRows: displayRows,
            displayKeys: displayKeys,
            data: data,
            viewMode: TableRowDetailViewMode.fields,
          );
        }
      case 'e':
      case 'E':
        if (activeKey == null) return;
        event.preventDefault();
        _openDetailForRowKey(
          context: context,
          rowKey: activeKey,
          displayRows: displayRows,
          displayKeys: displayKeys,
          data: data,
          viewMode: TableRowDetailViewMode.edit,
          viaEditShortcut: true,
        );
      case 'Escape':
        if (context.read(tableRowDetailProvider) != null) return;
        event.preventDefault();
        if (_hasHomeFocus(context)) {
          _clearHomeFocus(context);
          return;
        }
        if (context.read(tableRowSelectionProvider).isEmpty) return;
        selectionNotifier.clear();
      default:
        return;
    }
  }

  @override
  Component build(BuildContext context) => Component.empty();
}
