import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_routes.dart';
import '../constants/theme.dart';
import '../providers/app_name_provider.dart';
import '../providers/home_ui_provider.dart';
import '../providers/session_user_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../providers/table_focus_provider.dart';
import '../providers/table_row_keyboard_focus_provider.dart';
import '../utils/sqlite_table_utils.dart';
import 'app_tooltip_overlay.dart';
import '../providers/app_tooltip_provider.dart';
import '../constants/button_sizes.dart';
import '../constants/spacing.dart';
import 'theme/ui_styles.dart';
import 'theme/zonai_icon_button.dart';

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
    final viewsExpanded = ui.viewsExpanded;
    final appName = context.watch(appNameProvider);
    final tables = context.watch(sqliteTablesProvider);
    final initial = appName.isNotEmpty ? appName[0].toUpperCase() : 'Z';

    final userTables = [
      for (final t in tables.tables)
        if (!t.isView && !isSystemSqliteTable(t.sqliteName)) t,
    ];
    final systemTables = [
      for (final t in tables.tables)
        if (!t.isView && isSystemSqliteTable(t.sqliteName)) t,
    ];
    final viewTables = [for (final t in tables.tables) if (t.isView) t];
    final peekFocusedSystem = !systemExpanded && focused != null && isSystemSqliteTable(focused!.sqliteName);
    final peekFocusedView = !viewsExpanded && focused != null && focused!.isView;
    final panelShown = systemExpanded || peekFocusedSystem;
    final viewsPanelShown = viewsExpanded || peekFocusedView;

    final railTables = <SqliteTableRef>[
      ...userTables,
      if (focused != null && isSystemSqliteTable(focused!.sqliteName) && !userTables.contains(focused)) focused!,
      if (focused != null && focused!.isView && !userTables.contains(focused)) focused!,
    ];

    return aside(
      classes:
          'home-sidebar${collapsed ? ' home-sidebar--collapsed' : ''}${ui.sidebarToggling ? ' home-sidebar--toggling' : ''}${ui.mobileNavOpen ? ' home-sidebar--mobile-open' : ''}${ui.mobileNavClosing ? ' home-sidebar--mobile-closing' : ''}',
      [
        div(classes: 'home-sidebar-header', [
          a(href: AuthRoutes.toUrlPath(AuthRoutes.home), classes: 'home-sidebar-brand', [
            div(classes: 'home-sidebar-logo', [.text(initial)]),
            span(classes: 'home-sidebar-app-name', [.text(appName)]),
          ]),
          ZonaiIconButton(
            size: ZonaiIconButtonSize.xs,
            variant: ZonaiIconButtonVariant.ghost,
            classes: 'home-sidebar-toggle',
            attributes: {'aria-label': collapsed ? 'Expand sidebar' : 'Collapse sidebar'},
            events: appTooltipEvents(context, text: collapsed ? 'Expand sidebar' : 'Collapse sidebar'),
            onClick: () => context.read(homeUiProvider.notifier).toggleSidebar(),
            child: .text(collapsed ? '›' : '‹'),
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
                if (viewTables.isNotEmpty)
                  _CollapsibleTableGroup(
                    label: 'Views',
                    tables: viewTables,
                    focused: focused,
                    expanded: viewsExpanded,
                    panelShown: viewsPanelShown,
                    peekFocused: peekFocusedView,
                    onToggle: () => context.read(homeUiProvider.notifier).toggleViews(),
                  ),
                if (systemTables.isNotEmpty)
                  _CollapsibleTableGroup(
                    label: 'System',
                    tables: systemTables,
                    focused: focused,
                    expanded: systemExpanded,
                    panelShown: panelShown,
                    peekFocused: peekFocusedSystem,
                    onToggle: () => context.read(homeUiProvider.notifier).toggleSystemTables(),
                  ),
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
              children: [_TablesList(tables: railTables, focused: focused, collapsed: true)],
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
        raw: const {'box-shadow': 'var(--zonai-shadow-sm)', 'overflow-x': 'hidden'},
      ),
      css('&--toggling').styles(raw: const {'transition': 'width 0.2s ease'}),
      css('&--collapsed').styles(width: 52.px),
      css('.home-sidebar-panels').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        minHeight: .zero,
        position: Position.relative(),
        overflow: Overflow.hidden,
      ),
      css('.home-sidebar-panel').styles(raw: const {'transition': 'opacity 0.2s ease, visibility 0.2s ease'}),
      css(
        '.home-sidebar-panel--expanded',
      ).styles(flex: Flex(grow: 1, shrink: 1), minHeight: .zero, raw: const {'opacity': '1', 'visibility': 'visible'}),
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
        raw: const {'opacity': '1', 'visibility': 'visible', 'pointer-events': 'auto', 'position': 'relative'},
      ),
      css('.home-sidebar-header').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: Gap.all(ZonaiSpacing.s4),
        padding: .symmetric(horizontal: ZonaiSpacing.s6, vertical: ZonaiSpacing.s8),
        border: Border.only(
          bottom: BorderSide.solid(color: borderColor, width: 1.px),
        ),
        flex: Flex(grow: 0, shrink: 0),
        maxWidth: 100.percent,
        raw: const {'overflow-x': 'hidden'},
      ),
      css('&--collapsed .home-sidebar-header').styles(
        justifyContent: .center,
        padding: .symmetric(horizontal: ZonaiSpacing.s4, vertical: ZonaiSpacing.s8),
      ),
      css('&--collapsed .home-sidebar-brand').styles(display: .none),
      css('.home-sidebar-brand').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(ZonaiSpacing.s5),
        minWidth: .zero,
        overflow: Overflow.hidden,
        flex: Flex(grow: 1, shrink: 1),
        raw: const {'text-decoration': 'none', 'color': 'inherit'},
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
      css(
        '&--collapsed .home-sidebar-app-name',
      ).styles(flex: Flex(grow: 0, shrink: 0), raw: const {'max-width': '0', 'opacity': '0'}),
      css('.home-sidebar-expand-only').styles(
        overflow: Overflow.hidden,
        raw: const {'transition': 'opacity 0.2s ease, max-width 0.2s ease', 'max-width': '200px', 'opacity': '1'},
      ),
      css(
        '&--collapsed .home-sidebar-expand-only',
      ).styles(raw: const {'max-width': '0', 'opacity': '0', 'pointer-events': 'none'}),
      css('.home-sidebar-toggle').styles(flex: Flex(grow: 0, shrink: 0), fontWeight: .w600),
      css('.home-sidebar-body').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s5),
        padding: .symmetric(horizontal: ZonaiSpacing.s6, vertical: ZonaiSpacing.s6),
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
        gap: Gap.all(ZonaiSpacing.s2),
        padding: .symmetric(horizontal: ZonaiSpacing.s3, vertical: ZonaiSpacing.s4),
        overflow: Overflow.auto,
        minHeight: .zero,
        maxWidth: 100.percent,
        raw: const {'overflow-x': 'hidden'},
      ),
      css('.home-sidebar-msg').styles(fontSize: 0.8125.rem, color: mutedColor, margin: .zero),
      css(
        '.home-sidebar-error',
      ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s4)),
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
      css(
        '.home-sidebar-collapsible',
      ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2)),
      css('.home-sidebar-collapsible-toggle').styles(
        cursor: .pointer,
        padding: .symmetric(vertical: ZonaiSpacing.s2),
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(ZonaiSpacing.s3),
        width: 100.percent,
        border: Border.none,
        backgroundColor: Colors.transparent,
        textAlign: .left,
        raw: const {'font': 'inherit'},
      ),
      css(
        '.home-sidebar-collapsible-toggle:hover',
      ).styles(raw: const {'& .home-sidebar-collapsible-chevron': 'color: var(--zonai-fg)'}),
      css('.home-sidebar-collapsible-chevron').styles(
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
      css('.home-sidebar-collapsible-chevron--open').styles(raw: const {'transform': 'rotate(90deg)'}),
      css('.home-sidebar-collapsible-panel').styles(
        raw: const {'display': 'grid', 'grid-template-rows': '0fr', 'transition': 'grid-template-rows 0.2s ease'},
      ),
      css('.home-sidebar-collapsible-panel--shown').styles(raw: const {'grid-template-rows': '1fr'}),
      css('.home-sidebar-collapsible-panel-inner').styles(overflow: Overflow.hidden, minHeight: .zero),
      css('.home-sidebar-collapsible-panel .home-sidebar-item:not(.home-sidebar-item-focused)').styles(
        overflow: Overflow.hidden,
        raw: const {
          'max-height': '2.75rem',
          'transition': 'max-height 0.2s ease, margin-bottom 0.2s ease, opacity 0.2s ease',
        },
      ),
      css(
        '.home-sidebar-collapsible-panel--peek .home-sidebar-item:not(.home-sidebar-item-focused)',
      ).styles(margin: .zero, raw: const {'max-height': '0', 'opacity': '0', 'pointer-events': 'none'}),
      css('.home-sidebar-footer').styles(
        margin: .only(top: .auto),
        padding: .all(ZonaiSpacing.s6),
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
      ).styles(display: .flex, flexDirection: FlexDirection.column, alignItems: .center, gap: Gap.all(ZonaiSpacing.s4)),
      css('&--collapsed .home-sidebar-footer').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        alignItems: .center,
        padding: .symmetric(horizontal: ZonaiSpacing.s4, vertical: ZonaiSpacing.s6),
      ),
      css(
        '&--collapsed .home-sidebar-profile-trigger',
      ).styles(width: 36.px, height: 36.px, padding: .zero, justifyContent: .center, gap: Gap.all(ZonaiSpacing.s0)),
      css('&--collapsed .home-sidebar-profile-trigger .home-sidebar-expand-only').styles(display: .none),
      css('.home-sidebar-profile-trigger').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(ZonaiSpacing.s5),
        width: 100.percent,
        maxWidth: 100.percent,
        padding: .symmetric(horizontal: ZonaiSpacing.s4, vertical: ZonaiSpacing.s4),
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
      ).styles(width: ZonaiSpacing.s14, height: ZonaiSpacing.s14, padding: .zero, justifyContent: .center),
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
        gap: Gap.all(ZonaiSpacing.s2),
        width: 100.percent,
      ),
      css('.home-sidebar-item').styles(
        margin: .only(bottom: ZonaiSpacing.s1),
        maxWidth: 100.percent,
      ),
      css('.home-sidebar-item-button').styles(
        cursor: .pointer,
        display: .block,
        width: 100.percent,
        maxWidth: 100.percent,
        textAlign: .left,
        padding: .symmetric(horizontal: ZonaiSpacing.s5, vertical: ZonaiSpacing.s4),
        radius: .all(Radius.circular(8.px)),
        backgroundColor: Colors.transparent,
        border: Border.none,
        fontWeight: .w500,
        fontSize: 0.875.rem,
        color: fgColor,
        raw: const {'font': 'inherit', 'box-sizing': 'border-box'},
      ),
      css('.home-sidebar-item-button--rail').styles(display: .flex, fontSize: 0.75.rem, fontWeight: .w700),
      css('.home-sidebar-item:hover .home-sidebar-item-button').styles(backgroundColor: hoverColor),
      css(
        '.home-sidebar-item-focused .home-sidebar-item-button',
      ).styles(backgroundColor: selectedBgColor, color: primaryColor, fontWeight: .w600),
      css(
        '.home-sidebar-item--keyboard-focus .home-sidebar-item-button',
      ).styles(raw: const {'box-shadow': 'inset 0 0 0 2px var(--zonai-focus-ring)'}),
      css(
        '.home-sidebar-item-button--rail.home-sidebar-item-button--keyboard-focus',
      ).styles(raw: const {'box-shadow': '0 0 0 2px var(--zonai-focus-ring)'}),
    ]),
    css.media(MediaQuery.all(maxWidth: 640.px), [
      css('.home-sidebar').styles(
        position: Position.fixed(top: 0.px, left: 0.px, bottom: 0.px),
        width: 260.px,
        raw: const {'z-index': '150', 'transform': 'translateX(-100%)', 'transition': 'none'},
      ),
      css('.home-sidebar--collapsed').styles(width: 260.px),
      css(
        '.home-sidebar--mobile-open',
      ).styles(raw: const {'transform': 'translateX(0)', 'transition': 'transform 0.2s ease'}),
      css('.home-sidebar--mobile-closing').styles(raw: const {'transition': 'transform 0.2s ease'}),
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
  return itemRect.top >= portRect.top && itemRect.bottom <= portRect.bottom - _sidebarScrollBottomMarginPx;
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
          context.read(homeUiProvider.notifier).saveSidebarScrollTop(body: _isBody, scrollTop: el.scrollTop.toDouble());
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

    if (isSystemSqliteTable(focused.sqliteName) && !context.read(homeUiProvider).systemTablesExpanded) {
      context.read(homeUiProvider.notifier).setSystemTablesExpanded(true);
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }

    if (focused.isView && !context.read(homeUiProvider).viewsExpanded) {
      context.read(homeUiProvider.notifier).setViewsExpanded(true);
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
      context
          .read(homeUiProvider.notifier)
          .saveSidebarScrollTop(body: _isBody, scrollTop: scrollEl.scrollTop.toDouble());
    }
  }
}

/// A named, collapsible group of tables in the sidebar body — used for both
/// the "System" (framework-managed) and "Views" (read-only, query-defined)
/// groups, which share the same expand/collapse/peek behavior and styling.
class _CollapsibleTableGroup extends StatelessComponent {
  const _CollapsibleTableGroup({
    required this.label,
    required this.tables,
    required this.focused,
    required this.expanded,
    required this.panelShown,
    required this.peekFocused,
    required this.onToggle,
  });

  final String label;
  final List<SqliteTableRef> tables;
  final SqliteTableRef? focused;
  final bool expanded;
  final bool panelShown;
  final bool peekFocused;
  final void Function() onToggle;

  @override
  Component build(BuildContext context) {
    return div(classes: 'home-sidebar-collapsible', [
      button(
        classes: 'home-sidebar-collapsible-toggle',
        type: .button,
        attributes: {'aria-expanded': expanded ? 'true' : 'false'},
        onClick: onToggle,
        [
          span(
            classes: 'home-sidebar-collapsible-chevron${expanded ? ' home-sidebar-collapsible-chevron--open' : ''}',
            [.text('›')],
          ),
          span(classes: ZonaiClasses.sectionLabel, [.text(label)]),
        ],
      ),
      div(
        classes:
            'home-sidebar-collapsible-panel'
            '${panelShown ? ' home-sidebar-collapsible-panel--shown' : ''}'
            '${peekFocused ? ' home-sidebar-collapsible-panel--peek' : ''}',
        attributes: {'aria-hidden': panelShown ? 'false' : 'true'},
        [
          div(classes: 'home-sidebar-collapsible-panel-inner', [
            _TablesList(tables: tables, focused: focused, collapsed: false),
          ]),
        ],
      ),
    ]);
  }
}

class _TablesList extends StatelessComponent {
  const _TablesList({required this.tables, required this.focused, required this.collapsed});

  final List<SqliteTableRef> tables;
  final SqliteTableRef? focused;
  final bool collapsed;

  @override
  Component build(BuildContext context) {
    final keyboard = context.watch(tableRowKeyboardFocusProvider);
    final keyboardSidebarSqlite = keyboard.zone == HomeKeyboardFocusZone.sidebar
        ? keyboard.sidebarTableSqliteName
        : null;

    return ul(classes: collapsed ? 'home-sidebar-tables home-sidebar-tables--rail' : 'home-sidebar-tables', [
      for (final table in tables)
        li(
          classes:
              'home-sidebar-item'
              '${focused == table ? ' home-sidebar-item-focused' : ''}'
              '${keyboardSidebarSqlite == table.sqliteName ? ' home-sidebar-item--keyboard-focus' : ''}',
          attributes: {'id': _sidebarTableItemId(table.sqliteName)},
          [
            if (collapsed)
              _RailTableButton(
                table: table,
                label: _railLabel(table),
                keyboardFocused: keyboardSidebarSqlite == table.sqliteName,
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

class _RailTableButton extends StatelessComponent {
  const _RailTableButton({
    required this.table,
    required this.label,
    required this.keyboardFocused,
    required this.onSelect,
  });

  final SqliteTableRef table;
  final String label;
  final bool keyboardFocused;
  final void Function() onSelect;

  @override
  Component build(BuildContext context) {
    final parts = <String>['home-sidebar-item-button', 'home-sidebar-item-button--rail'];
    if (keyboardFocused) parts.add('home-sidebar-item-button--keyboard-focus');
    return ZonaiIconButton(
      size: ZonaiIconButtonSize.md,
      variant: ZonaiIconButtonVariant.ghost,
      classes: parts.join(' '),
      attributes: {'aria-label': table.displayName},
      events: appTooltipEvents(context, text: table.displayName, placement: AppTooltipPlacement.rightCenter),
      onClick: onSelect,
      child: .text(label),
    );
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
          'aria-label': 'Account and settings',
          'aria-haspopup': 'dialog',
          'aria-expanded': settingsOpen ? 'true' : 'false',
        },
        onClick: () => context.read(homeUiProvider.notifier).toggleSettings(),
        [
          div(classes: 'home-sidebar-avatar', [.text(initial)]),
          div(classes: 'home-sidebar-profile-text home-sidebar-expand-only', [
            span(classes: 'home-sidebar-email', [.text(label)]),
            if (sessionUser?.isAdmin == true) span(classes: 'home-sidebar-badge', [.text('Admin')]),
          ]),
          span(classes: 'home-sidebar-settings-icon home-sidebar-expand-only', [.text('⚙')]),
        ],
      ),
    ]);
  }
}
