import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../constants/theme.dart';
import '../providers/app_name_provider.dart';
import '../providers/home_ui_provider.dart';
import '../providers/session_user_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../providers/table_focus_provider.dart';
import '../utils/sqlite_table_utils.dart';
import 'theme/ui_styles.dart';

String _sidebarTableItemId(String sqliteName) => 'home-sidebar-table-$sqliteName';

class HomeSidebar extends StatelessComponent {
  const HomeSidebar({super.key, required this.focused});

  final SqliteTableRef? focused;

  @override
  Component build(BuildContext context) {
    final ui = context.watch(homeUiProvider);
    // Mobile drawer always shows full table list while open.
    final collapsed = ui.sidebarVisuallyCollapsed;
    final systemExpanded = ui.systemTablesExpanded;
    final appName = context.watch(appNameProvider);
    final tables = context.watch(sqliteTablesProvider);
    final initial = appName.isNotEmpty ? appName[0].toUpperCase() : 'Z';

    final userTables = [
      for (final t in tables.tables)
        if (!isSystemSqliteTable(t.sqliteName)) t,
    ];
    final systemTables = [
      for (final t in tables.tables)
        if (isSystemSqliteTable(t.sqliteName)) t,
    ];

    final railTables = <SqliteTableRef>[
      ...userTables,
      if (focused != null && isSystemSqliteTable(focused!.sqliteName) && !userTables.contains(focused)) focused!,
    ];

    return aside(
      classes:
          'home-sidebar${collapsed ? ' home-sidebar--collapsed' : ''}${ui.mobileNavOpen ? ' home-sidebar--mobile-open' : ''}',
      [
        div(classes: 'home-sidebar-header', [
          div(classes: 'home-sidebar-brand', [
            div(classes: 'home-sidebar-logo', [.text(initial)]),
            span(classes: 'home-sidebar-app-name', [.text(appName)]),
          ]),
          button(
            classes: 'home-sidebar-toggle',
            type: .button,
            attributes: {
              'title': collapsed ? 'Expand sidebar' : 'Collapse sidebar',
              'aria-label': collapsed ? 'Expand sidebar' : 'Collapse sidebar',
            },
            onClick: () => context.read(homeUiProvider.notifier).toggleSidebar(),
            [.text(collapsed ? '›' : '‹')],
          ),
        ]),
        div(classes: 'home-sidebar-panels', [
          _SidebarListArea(
            regionClass: 'home-sidebar-body',
            panelClass: 'home-sidebar-panel home-sidebar-panel--expanded',
            focused: focused,
            collapsed: false,
            mobileNavOpen: ui.mobileNavOpen,
            children: [
              if (tables.loadError case final error?)
                div(classes: 'home-sidebar-error', [
                  p(classes: 'home-sidebar-msg', [.text('Could not load tables.')]),
                  pre(classes: 'home-sidebar-err-detail', [.text(error)]),
                ])
              else if (tables.tables.isEmpty)
                p(classes: 'home-sidebar-msg', [.text('No tables yet.')])
              else ...[
                if (userTables.isNotEmpty) ...[
                  p(classes: ZonaiClasses.sectionLabel, [.text('Tables')]),
                  _TablesList(tables: userTables, focused: focused, collapsed: false),
                ],
                if (systemTables.isNotEmpty)
                  div(classes: 'home-sidebar-system', [
                    button(
                      classes: 'home-sidebar-system-toggle',
                      type: .button,
                      attributes: {'aria-expanded': systemExpanded ? 'true' : 'false'},
                      onClick: () => context.read(homeUiProvider.notifier).toggleSystemTables(),
                      [
                        span(
                          classes:
                              'home-sidebar-system-chevron${systemExpanded ? ' home-sidebar-system-chevron--open' : ''}',
                          [.text('›')],
                        ),
                        span(classes: ZonaiClasses.sectionLabel, [.text('System')]),
                      ],
                    ),
                    if (systemExpanded) _TablesList(tables: systemTables, focused: focused, collapsed: false),
                  ]),
              ],
            ],
          ),
          if (railTables.isNotEmpty)
            _SidebarListArea(
              regionClass: 'home-sidebar-rail',
              panelClass: 'home-sidebar-panel home-sidebar-panel--rail',
              focused: focused,
              collapsed: true,
              mobileNavOpen: ui.mobileNavOpen,
              children: [
                _TablesList(tables: railTables, focused: focused, collapsed: true),
              ],
            ),
        ]),
        const _SidebarFooter(),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.home-sidebar', [
      css('&').styles(
        width: 260.px,
        flex: Flex(grow: 0, shrink: 0),
        backgroundColor: surfaceColor,
        border: Border.only(
          right: BorderSide.solid(color: borderColor, width: 1.px),
        ),
        display: .flex,
        flexDirection: FlexDirection.column,
        minHeight: .zero,
        overflow: Overflow.hidden,
        raw: const {
          'box-shadow': 'var(--zonai-shadow-sm)',
          'overflow-x': 'hidden',
          'transition': 'width 0.2s ease',
        },
      ),
      css('&--collapsed').styles(width: 52.px),
      css('.home-sidebar-panels').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        minHeight: .zero,
        position: Position.relative(),
        overflow: Overflow.hidden,
      ),
      css('.home-sidebar-panel').styles(
        raw: const {'transition': 'opacity 0.2s ease, visibility 0.2s ease'},
      ),
      css('.home-sidebar-panel--expanded').styles(
        flex: Flex(grow: 1, shrink: 1),
        minHeight: .zero,
        raw: const {'opacity': '1', 'visibility': 'visible'},
      ),
      css('.home-sidebar-panel--rail').styles(
        raw: const {
          'opacity': '0',
          'visibility': 'hidden',
          'pointer-events': 'none',
          'position': 'absolute',
          'inset': '0',
        },
      ),
      css('&--collapsed .home-sidebar-panel--expanded').styles(
        raw: const {
          'opacity': '0',
          'visibility': 'hidden',
          'pointer-events': 'none',
          'position': 'absolute',
          'inset': '0',
          'flex': 'none',
        },
      ),
      css('&--collapsed .home-sidebar-panel--rail').styles(
        flex: Flex(grow: 1, shrink: 1),
        minHeight: .zero,
        raw: const {
          'opacity': '1',
          'visibility': 'visible',
          'pointer-events': 'auto',
          'position': 'relative',
        },
      ),
      css('.home-sidebar-header').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: Gap.all(8.px),
        padding: .symmetric(horizontal: 12.px, vertical: 16.px),
        border: Border.only(
          bottom: BorderSide.solid(color: borderColor, width: 1.px),
        ),
        flex: Flex(grow: 0, shrink: 0),
        maxWidth: 100.percent,
        raw: const {'overflow-x': 'hidden'},
      ),
      css('&--collapsed .home-sidebar-header').styles(
        justifyContent: .center,
        padding: .symmetric(horizontal: 8.px, vertical: 16.px),
      ),
      css('&--collapsed .home-sidebar-brand').styles(display: .none),
      css('.home-sidebar-brand').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(10.px),
        minWidth: .zero,
        overflow: Overflow.hidden,
        flex: Flex(grow: 1, shrink: 1),
      ),
      css('.home-sidebar-logo').styles(
        width: 32.px,
        height: 32.px,
        flex: Flex(grow: 0, shrink: 0),
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        radius: .all(Radius.circular(8.px)),
        backgroundColor: primaryColor,
        color: onPrimaryColor,
        fontSize: 0.875.rem,
        fontWeight: .w700,
      ),
      css('.home-sidebar-app-name').styles(
        fontSize: 0.875.rem,
        fontWeight: .w600,
        overflow: Overflow.hidden,
        flex: Flex(grow: 1, shrink: 1),
        minWidth: .zero,
        raw: const {
          'text-overflow': 'ellipsis',
          'white-space': 'nowrap',
          'transition': 'opacity 0.2s ease, max-width 0.2s ease, flex-grow 0.2s ease',
          'max-width': '200px',
          'opacity': '1',
        },
      ),
      css('&--collapsed .home-sidebar-app-name').styles(
        flex: Flex(grow: 0, shrink: 0),
        raw: const {'max-width': '0', 'opacity': '0'},
      ),
      css('.home-sidebar-expand-only').styles(
        overflow: Overflow.hidden,
        raw: const {
          'transition': 'opacity 0.2s ease, max-width 0.2s ease',
          'max-width': '200px',
          'opacity': '1',
        },
      ),
      css('&--collapsed .home-sidebar-expand-only').styles(
        raw: const {'max-width': '0', 'opacity': '0', 'pointer-events': 'none'},
      ),
      css('.home-sidebar-toggle').styles(
        flex: Flex(grow: 0, shrink: 0),
        width: 28.px,
        height: 28.px,
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        cursor: .pointer,
        radius: .all(Radius.circular(6.px)),
        border: Border.none,
        backgroundColor: Colors.transparent,
        color: mutedColor,
        fontSize: 1.125.rem,
        fontWeight: .w600,
        padding: .zero,
        raw: const {'font': 'inherit', 'line-height': '1'},
      ),
      css('.home-sidebar-toggle:hover').styles(backgroundColor: hoverColor, color: fgColor),
      css('.home-sidebar-body').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(10.px),
        padding: .symmetric(horizontal: 12.px, vertical: 12.px),
        overflow: Overflow.auto,
        minHeight: .zero,
        maxWidth: 100.percent,
        raw: const {'overflow-x': 'hidden'},
      ),
      css('.home-sidebar-rail').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        alignItems: .center,
        gap: Gap.all(4.px),
        padding: .symmetric(horizontal: 6.px, vertical: 8.px),
        overflow: Overflow.auto,
        minHeight: .zero,
        maxWidth: 100.percent,
        raw: const {'overflow-x': 'hidden'},
      ),
      css('.home-sidebar-msg').styles(fontSize: 0.8125.rem, color: mutedColor, margin: .zero),
      css('.home-sidebar-error').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(8.px)),
      css('.home-sidebar-err-detail').styles(
        fontSize: 0.75.rem,
        color: errorColor,
        margin: .zero,
        raw: const {
          'overflow-wrap': 'anywhere',
          'white-space': 'pre-wrap',
          'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
        },
      ),
      css('.home-sidebar-system').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(4.px)),
      css('.home-sidebar-system-toggle').styles(
        cursor: .pointer,
        padding: .symmetric(vertical: 4.px),
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(6.px),
        width: 100.percent,
        border: Border.none,
        backgroundColor: Colors.transparent,
        textAlign: .left,
        raw: const {'font': 'inherit'},
      ),
      css(
        '.home-sidebar-system-toggle:hover',
      ).styles(raw: const {'& .home-sidebar-system-chevron': 'color: var(--zonai-fg)'}),
      css('.home-sidebar-system-chevron').styles(
        display: .inlineFlex,
        alignItems: .center,
        justifyContent: .center,
        width: 14.px,
        fontSize: 0.875.rem,
        fontWeight: .w700,
        color: mutedColor,
        flex: Flex(grow: 0, shrink: 0),
        raw: const {'line-height': '1', 'transition': 'transform 0.15s ease'},
      ),
      css('.home-sidebar-system-chevron--open').styles(raw: const {'transform': 'rotate(90deg)'}),
      css('.home-sidebar-footer').styles(
        margin: .only(top: .auto),
        padding: .all(12.px),
        border: Border.only(
          top: BorderSide.solid(color: borderColor, width: 1.px),
        ),
        backgroundColor: bgColor,
        flex: Flex(grow: 0, shrink: 0),
        maxWidth: 100.percent,
        raw: const {'overflow-x': 'hidden'},
      ),
      css(
        '.home-sidebar-footer--collapsed',
      ).styles(display: .flex, flexDirection: FlexDirection.column, alignItems: .center, gap: Gap.all(8.px)),
      css('&--collapsed .home-sidebar-footer').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        alignItems: .center,
        padding: .symmetric(horizontal: 8.px, vertical: 12.px),
      ),
      css('&--collapsed .home-sidebar-profile-trigger').styles(
        width: 36.px,
        height: 36.px,
        padding: .zero,
        justifyContent: .center,
        gap: Gap.all(0.px),
      ),
      css('&--collapsed .home-sidebar-profile-trigger .home-sidebar-expand-only').styles(display: .none),
      css('.home-sidebar-profile-trigger').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(10.px),
        width: 100.percent,
        maxWidth: 100.percent,
        padding: .symmetric(horizontal: 8.px, vertical: 8.px),
        cursor: .pointer,
        radius: .all(Radius.circular(8.px)),
        border: Border.none,
        backgroundColor: Colors.transparent,
        textAlign: .left,
        raw: const {'font': 'inherit', 'box-sizing': 'border-box'},
      ),
      css('.home-sidebar-profile-trigger:hover').styles(backgroundColor: hoverColor),
      css(
        '.home-sidebar-profile-trigger--collapsed',
      ).styles(width: 36.px, height: 36.px, padding: .zero, justifyContent: .center),
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
      css('.home-sidebar-settings-icon').styles(
        margin: .only(left: .auto),
        flex: Flex(grow: 0, shrink: 0),
        fontSize: 1.125.rem,
        color: mutedColor,
      ),
      css(
        '.home-sidebar-tables',
      ).styles(margin: .zero, padding: .zero, listStyle: .none, width: 100.percent, maxWidth: 100.percent),
      css('.home-sidebar-tables--rail').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        alignItems: .center,
        gap: Gap.all(4.px),
        width: 100.percent,
      ),
      css('.home-sidebar-item').styles(
        margin: .only(bottom: 2.px),
        maxWidth: 100.percent,
      ),
      css('.home-sidebar-item-button').styles(
        cursor: .pointer,
        display: .block,
        width: 100.percent,
        maxWidth: 100.percent,
        textAlign: .left,
        padding: .symmetric(horizontal: 10.px, vertical: 8.px),
        radius: .all(Radius.circular(8.px)),
        backgroundColor: Colors.transparent,
        border: Border.none,
        fontWeight: .w500,
        fontSize: 0.875.rem,
        color: fgColor,
        raw: const {'font': 'inherit', 'box-sizing': 'border-box'},
      ),
      css('.home-sidebar-item-button--rail').styles(
        width: 36.px,
        height: 36.px,
        padding: .zero,
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        fontSize: 0.75.rem,
        fontWeight: .w700,
      ),
      css('.home-sidebar-item:hover .home-sidebar-item-button').styles(backgroundColor: hoverColor),
      css(
        '.home-sidebar-item-focused .home-sidebar-item-button',
      ).styles(backgroundColor: selectedBgColor, color: primaryColor, fontWeight: .w600),
      css('.home-rail-tooltip').styles(
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
          'transform': 'translateY(-50%)',
          'opacity': '0',
          'visibility': 'hidden',
          'transition': 'opacity 0.15s ease, visibility 0.15s ease',
        },
      ),
      css('.home-rail-tooltip--visible').styles(raw: const {'opacity': '1', 'visibility': 'visible'}),
    ]),
    css.media(MediaQuery.all(maxWidth: 640.px), [
      css('.home-sidebar').styles(
        position: Position.fixed(top: 0.px, left: 0.px, bottom: 0.px),
        width: 260.px,
        raw: const {'z-index': '150', 'transform': 'translateX(-100%)', 'transition': 'transform 0.2s ease'},
      ),
      css('.home-sidebar--collapsed').styles(width: 260.px),
      css('.home-sidebar--mobile-open').styles(raw: const {'transform': 'translateX(0)'}),
      css('.home-sidebar-toggle').styles(display: .none),
      css('.home-sidebar-panel--rail').styles(display: .none),
      css('.home-sidebar-panel--expanded').styles(
        raw: const {
          'opacity': '1',
          'visibility': 'visible',
          'pointer-events': 'auto',
          'position': 'relative',
          'inset': 'auto',
        },
      ),
      css('.home-sidebar--collapsed .home-sidebar-panel--expanded').styles(
        raw: const {
          'opacity': '1',
          'visibility': 'visible',
          'pointer-events': 'auto',
          'position': 'relative',
          'inset': 'auto',
        },
      ),
    ]),
  ];
}

const _sidebarScrollBottomMarginPx = 8.0;

bool _sidebarRowFullyVisible(web.Element item, web.Element port) {
  final itemRect = item.getBoundingClientRect();
  final portRect = port.getBoundingClientRect();
  return itemRect.top >= portRect.top &&
      itemRect.bottom <= portRect.bottom - _sidebarScrollBottomMarginPx;
}

void _sidebarScrollToRevealRow(web.Element scrollEl, web.Element item) {
  final itemRect = item.getBoundingClientRect();
  final portRect = scrollEl.getBoundingClientRect();
  final bottomLimit = portRect.bottom - _sidebarScrollBottomMarginPx;
  var delta = 0.0;
  if (itemRect.bottom > bottomLimit) {
    delta += itemRect.bottom - bottomLimit;
  }
  if (itemRect.top < portRect.top) {
    delta += itemRect.top - portRect.top;
  }
  if (delta != 0) {
    scrollEl.scrollTop = scrollEl.scrollTop + delta;
  }
}

/// Scrollport for the sidebar table list; saves scroll and reveals the focused row when needed.
class _SidebarListArea extends StatefulComponent {
  const _SidebarListArea({
    required this.regionClass,
    this.panelClass,
    required this.focused,
    required this.collapsed,
    required this.mobileNavOpen,
    required this.children,
  });

  final String regionClass;
  final String? panelClass;
  final SqliteTableRef? focused;
  final bool collapsed;
  final bool mobileNavOpen;
  final List<Component> children;

  @override
  State<_SidebarListArea> createState() => _SidebarListAreaState();
}

class _SidebarListAreaState extends State<_SidebarListArea> {
  String? _lastAlignedFocus;
  bool _lastCollapsed = true;
  bool _lastMobileNavOpen = false;

  bool get _isBody => component.regionClass == 'home-sidebar-body';

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_restoreSavedScroll);
  }

  @override
  Component build(BuildContext context) {
    _scheduleScrollWork();
    final classes = component.panelClass == null
        ? component.regionClass
        : '${component.regionClass} ${component.panelClass}';
    return div(
      classes: classes,
      events: {
        'scroll': (web.Event event) {
          if (!context.binding.isClient) return;
          final el = event.currentTarget;
          if (el is! web.Element) return;
          context.read(homeUiProvider.notifier).saveSidebarScrollTop(
            body: _isBody,
            scrollTop: el.scrollTop.toDouble(),
          );
        },
      },
      component.children,
    );
  }

  void _scheduleScrollWork() {
    if (!context.binding.isClient) return;

    final focused = component.focused;
    if (focused == null) return;

    final sqlite = focused.sqliteName;
    final focusChanged = sqlite != _lastAlignedFocus;
    final collapsedChanged = component.collapsed != _lastCollapsed;
    final mobileOpened = component.mobileNavOpen && !_lastMobileNavOpen;

    _lastAlignedFocus = sqlite;
    _lastCollapsed = component.collapsed;
    _lastMobileNavOpen = component.mobileNavOpen;

    if (!focusChanged && !collapsedChanged && !mobileOpened) return;

    scheduleMicrotask(() async {
      if (mobileOpened || collapsedChanged) {
        await _restoreSavedScroll();
      }
      if (focusChanged || mobileOpened || collapsedChanged) {
        await _ensureFocusedRowFullyVisible();
      }
    });
  }

  Future<void> _restoreSavedScroll() async {
    if (!mounted || !context.binding.isClient) return;

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final scrollEl = web.document.querySelector('.${component.regionClass}');
    if (scrollEl == null) return;

    final top = context.read(homeUiProvider.notifier).savedSidebarScrollTopFor(body: _isBody);
    scrollEl.scrollTop = top;
  }

  Future<void> _ensureFocusedRowFullyVisible() async {
    if (!mounted || !context.binding.isClient) return;

    final focused = component.focused;
    if (focused == null) return;

    if (isSystemSqliteTable(focused.sqliteName) &&
        !context.read(homeUiProvider).systemTablesExpanded) {
      context.read(homeUiProvider.notifier).setSystemTablesExpanded(true);
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final scrollEl = web.document.querySelector('.${component.regionClass}');
    final item = web.document.getElementById(_sidebarTableItemId(focused.sqliteName));
    if (scrollEl == null || item == null) return;

    if (!_sidebarRowFullyVisible(item, scrollEl)) {
      _sidebarScrollToRevealRow(scrollEl, item);
      context.read(homeUiProvider.notifier).saveSidebarScrollTop(
        body: _isBody,
        scrollTop: scrollEl.scrollTop.toDouble(),
      );
    }
  }
}

class _TablesList extends StatelessComponent {
  const _TablesList({required this.tables, required this.focused, required this.collapsed});

  final List<SqliteTableRef> tables;
  final SqliteTableRef? focused;
  final bool collapsed;

  @override
  Component build(BuildContext context) {
    return ul(classes: collapsed ? 'home-sidebar-tables home-sidebar-tables--rail' : 'home-sidebar-tables', [
      for (final table in tables)
        li(
          classes: 'home-sidebar-item${focused == table ? ' home-sidebar-item-focused' : ''}',
          attributes: {'id': _sidebarTableItemId(table.sqliteName)},
          [
            if (collapsed)
              _RailTableButton(
                table: table,
                label: _railLabel(table),
                focused: focused == table,
                onSelect: () {
                  context.read(homeUiProvider.notifier).captureSidebarScrollFromDom();
                  context.read(homeUiProvider.notifier).closeMobileNav();
                  context.read(tableFocusProvider.notifier).setFocused(context, table);
                },
              )
            else
              button(
                [.text(table.displayName)],
                type: .button,
                classes: 'home-sidebar-item-button',
                onClick: () {
                  context.read(homeUiProvider.notifier).captureSidebarScrollFromDom();
                  context.read(homeUiProvider.notifier).closeMobileNav();
                  context.read(tableFocusProvider.notifier).setFocused(context, table);
                },
              ),
          ],
        ),
    ]);
  }

  static String _railLabel(SqliteTableRef table) {
    final name = table.displayName;
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }
}

class _RailTableButton extends StatefulComponent {
  const _RailTableButton({required this.table, required this.label, required this.focused, required this.onSelect});

  final SqliteTableRef table;
  final String label;
  final bool focused;
  final void Function() onSelect;

  @override
  State<_RailTableButton> createState() => _RailTableButtonState();
}

class _RailTableButtonState extends State<_RailTableButton> {
  bool _tooltipVisible = false;
  double _tooltipTop = 0;
  double _tooltipLeft = 0;

  void _showTooltip(web.Event event) {
    if (!context.binding.isClient) return;
    final el = event.currentTarget;
    if (el is! web.HTMLElement) return;
    final rect = el.getBoundingClientRect();
    setState(() {
      _tooltipVisible = true;
      _tooltipTop = rect.top + rect.height / 2;
      _tooltipLeft = rect.right + 8;
    });
  }

  void _hideTooltip(_) {
    if (_tooltipVisible) {
      setState(() => _tooltipVisible = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final tooltipStyle = _tooltipVisible ? 'top: ${_tooltipTop}px; left: ${_tooltipLeft}px;' : '';

    return Component.fragment([
      button(
        [.text(component.label)],
        type: .button,
        classes: component.focused
            ? 'home-sidebar-item-button home-sidebar-item-button--rail'
            : 'home-sidebar-item-button home-sidebar-item-button--rail',
        attributes: {'aria-label': component.table.displayName},
        onClick: component.onSelect,
        events: {'mouseenter': _showTooltip, 'mouseleave': _hideTooltip, 'focus': _showTooltip, 'blur': _hideTooltip},
      ),
      if (context.binding.isClient)
        span(
          classes: 'home-rail-tooltip${_tooltipVisible ? ' home-rail-tooltip--visible' : ''}',
          attributes: {'role': 'tooltip', if (tooltipStyle.isNotEmpty) 'style': tooltipStyle},
          [.text(component.table.displayName)],
        ),
    ]);
  }
}

class _SidebarFooter extends StatelessComponent {
  const _SidebarFooter();

  @override
  Component build(BuildContext context) {
    final ui = context.watch(homeUiProvider);
    final collapsed = ui.sidebarVisuallyCollapsed;
    final settingsOpen = ui.settingsOpen;
    final sessionUser = context.watch(sessionUserProvider);
    final label = sessionUser?.label ?? 'Account';
    final initial = sessionUser?.initial ?? '?';

    return div(classes: collapsed ? 'home-sidebar-footer home-sidebar-footer--collapsed' : 'home-sidebar-footer', [
      button(
        classes: collapsed
            ? 'home-sidebar-profile-trigger home-sidebar-profile-trigger--collapsed'
            : 'home-sidebar-profile-trigger',
        type: .button,
        attributes: {
          'title': 'Account and settings',
          'aria-label': 'Account and settings',
          'aria-haspopup': 'dialog',
          'aria-expanded': settingsOpen ? 'true' : 'false',
        },
        onClick: () => context.read(homeUiProvider.notifier).toggleSettings(),
        [
          div(classes: 'home-sidebar-avatar', [.text(initial)]),
          div(classes: 'home-sidebar-profile-text home-sidebar-expand-only', [
            span(classes: 'home-sidebar-email', attributes: {'title': label}, [.text(label)]),
            if (sessionUser?.isAdmin == true) span(classes: 'home-sidebar-badge', [.text('Admin')]),
          ]),
          span(classes: 'home-sidebar-settings-icon home-sidebar-expand-only', [.text('⚙')]),
        ],
      ),
    ]);
  }
}
