/// The docs sidebar: collapsible, icon-labelled groups driven by
/// `lib/src/navigation.dart`.
///
/// Replaces `jaspr_content`'s flat [Sidebar], which renders every group
/// expanded. With thirteen groups and seventy-odd pages that is a long scroll
/// with no landmarks; collapsing all but the active group turns it into a
/// thirteen-line menu.
///
/// Built on `<details>`/`<summary>` so it collapses without JavaScript and is
/// keyboard- and screen-reader-navigable for free.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import '../src/navigation.dart';

/// A sidebar rendered from [navigation], with the group owning the current
/// route expanded.
class DocsSidebar extends StatelessComponent {
  const DocsSidebar({this.currentRoute, super.key});

  /// The route to mark active. Defaults to the current page's url.
  final String? currentRoute;

  @override
  Component build(BuildContext context) {
    final route = currentRoute ?? context.page.url;
    final activeGroup = groupFor(route);

    return Component.fragment([
      Document.head(children: [Style(styles: _styles)]),
      nav(classes: 'docs-sidebar', attributes: {'aria-label': 'Documentation'}, [
        button(classes: 'sidebar-close', attributes: {'aria-label': 'Close navigation'}, [RawText(_closeIcon)]),
        ul(classes: 'docs-sidebar-top', [
          for (final item in topLevelNavigation) _link(item, route),
        ]),
        for (final group in navigation)
          details(
            classes: 'docs-sidebar-group',
            // The active group is the only one open on load; on the landing
            // page nothing is active, so open the first group as a starting
            // point rather than presenting a fully collapsed menu.
            open: identical(group, activeGroup) || (activeGroup == null && identical(group, navigation.first)),
            [
              summary(classes: 'docs-sidebar-summary', [
                span(classes: 'docs-sidebar-icon', [RawText(group.icon)]),
                span(classes: 'docs-sidebar-title', [Component.text(group.title)]),
                span(classes: 'docs-sidebar-chevron', [RawText(_chevronIcon)]),
              ]),
              ul([for (final item in group.items) _link(item, route)]),
            ],
          ),
      ]),
    ]);
  }

  Component _link(NavItem item, String route) {
    final isActive = item.href == route;
    return li([
      a(
        href: item.href,
        classes: isActive ? 'docs-sidebar-link active' : 'docs-sidebar-link',
        attributes: {if (isActive) 'aria-current': 'page'},
        [
          span([Component.text(item.title)]),
          if (item.badge case final badge?) span(classes: 'docs-sidebar-badge', [Component.text(badge)]),
        ],
      ),
    ]);
  }
}

const _chevronIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" '
    'stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
    '<path d="m9 18 6-6-6-6"/></svg>';

const _closeIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" '
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
    '<path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>';

List<StyleRule> get _styles => [
  css('.docs-sidebar', [
    css('&').styles(
      position: Position.relative(),
      fontSize: .875.rem,
      lineHeight: 1.25.rem,
      padding: Padding.only(left: .5.rem, right: .75.rem, bottom: 2.rem, top: .75.rem),
    ),
    css.media(MediaQuery.all(minWidth: 1024.px), [css('&').styles(padding: Padding.only(top: 1.rem))]),

    css('.sidebar-close', [
      css('&').styles(
        position: Position.absolute(top: .75.rem, right: .75.rem),
        border: Border.unset,
        backgroundColor: Colors.transparent,
        color: Color('inherit'),
        cursor: Cursor.pointer,
      ),
      css.media(MediaQuery.all(minWidth: 1024.px), [css('&').styles(display: Display.none)]),
    ]),

    css('ul').styles(listStyle: ListStyle.none, margin: Margin.zero, padding: Padding.zero),

    css('.docs-sidebar-top').styles(margin: Margin.only(bottom: .5.rem)),

    css('.docs-sidebar-link', [
      css('&').styles(
        display: Display.flex,
        alignItems: AlignItems.center,
        gap: Gap.column(.5.rem),
        opacity: .75,
        margin: Margin.only(bottom: 1.px),
        padding: Padding.symmetric(horizontal: .75.rem, vertical: .375.rem),
        radius: BorderRadius.circular(.375.rem),
        textDecoration: TextDecoration.none,
        color: Color('inherit'),
        transition: Transition('all', duration: 150.ms, curve: Curve.easeInOut),
      ),
      css('&:hover').styles(opacity: 1, backgroundColor: Color('color-mix(in srgb, currentColor 6%, transparent)')),
      css('&.active').styles(
        opacity: 1,
        color: ContentColors.primary,
        fontWeight: FontWeight.w600,
        backgroundColor: Color('color-mix(in srgb, currentColor 14%, transparent)'),
      ),
      css('span:first-child').styles(
        overflow: Overflow.hidden,
        textOverflow: TextOverflow.ellipsis,
        whiteSpace: WhiteSpace.noWrap,
      ),
    ]),

    css('.docs-sidebar-badge').styles(
      flex: Flex(shrink: 0),
      padding: Padding.symmetric(horizontal: .3125.rem),
      radius: BorderRadius.circular(999.px),
      fontSize: .625.rem,
      fontWeight: FontWeight.w700,
      textTransform: TextTransform.upperCase,
      letterSpacing: .03.em,
      color: ContentColors.primary,
      backgroundColor: Color('color-mix(in srgb, currentColor 15%, transparent)'),
    ),

    css('.docs-sidebar-group', [
      css('& > ul').styles(
        margin: Margin.only(bottom: .5.rem, left: 1.0625.rem),
        padding: Padding.only(left: .5.rem),
        border: Border.only(left: BorderSide(width: 1.px, color: Color('color-mix(in srgb, currentColor 12%, transparent)'))),
      ),
      css('&[open] .docs-sidebar-chevron svg').styles(transform: Transform.rotate(90.deg)),
    ]),

    css('.docs-sidebar-summary', [
      css('&').styles(
        display: Display.flex,
        alignItems: AlignItems.center,
        gap: Gap.column(.5.rem),
        padding: Padding.symmetric(horizontal: .5.rem, vertical: .4375.rem),
        radius: BorderRadius.circular(.375.rem),
        cursor: Cursor.pointer,
        fontWeight: FontWeight.w600,
        listStyle: ListStyle.none,
        userSelect: UserSelect.none,
      ),
      css('&::-webkit-details-marker').styles(display: Display.none),
      css('&:hover').styles(backgroundColor: Color('color-mix(in srgb, currentColor 6%, transparent)')),
      css('.docs-sidebar-icon').styles(display: Display.flex, opacity: .6, flex: Flex(shrink: 0)),
      css('.docs-sidebar-title').styles(flex: Flex(grow: 1)),
      css('.docs-sidebar-chevron', [
        css('&').styles(display: Display.flex, opacity: .45),
        css('svg').styles(transition: Transition('transform', duration: 150.ms, curve: Curve.easeInOut)),
      ]),
    ]),
  ]),
];
