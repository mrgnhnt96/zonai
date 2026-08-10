/// Card components for the landing page and section hubs.
///
/// Usable directly from markdown:
///
/// ```md
/// <CardGrid>
///
/// <Card title="Quick Start" href="/getting-started/quick-start" icon="rocket">
///
/// Create a project, define tables, migrate, and hit your first endpoint.
///
/// </Card>
///
/// </CardGrid>
/// ```
///
/// The blank lines matter: `package:markdown` treats an HTML block as literal
/// text until a blank line, so without them the card body renders with its
/// `**` and `[]()` intact.
///
/// [SectionCards] takes no children and renders one card per [NavGroup], so the
/// landing page's section index cannot drift from the sidebar.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import '../src/navigation.dart';

/// `<CardGrid columns="3">` — a responsive grid wrapper for [Card]s.
final class CardGrid extends CustomComponentBase {
  const CardGrid();

  @override
  Pattern get pattern => 'CardGrid';

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) {
    final columns = int.tryParse(attributes['columns'] ?? '') ?? 2;
    return Component.fragment([
      Document.head(children: [Style(styles: _styles)]),
      div(
        classes: 'card-grid',
        attributes: {'data-columns': '${columns.clamp(1, 4)}'},
        [if (child != null) child],
      ),
    ]);
  }
}

/// `<Card title="…" href="…" icon="…" badge="…">` — a linked summary tile.
final class Card extends CustomComponentBase {
  const Card();

  @override
  Pattern get pattern => 'Card';

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) {
    final title = attributes['title'] ?? '';
    final href = attributes['href'];
    final icon = _iconsByName[attributes['icon']];

    final body = [
      div(classes: 'card-head', [
        if (icon != null) span(classes: 'card-icon', [RawText(icon)]),
        span(classes: 'card-title', [Component.text(title)]),
        if (attributes['badge'] case final badge?) span(classes: 'card-badge', [Component.text(badge)]),
      ]),
      if (child != null) div(classes: 'card-body', [child]),
    ];

    return Component.fragment([
      Document.head(children: [Style(styles: _styles)]),
      if (href != null) a(classes: 'card', href: href, body) else div(classes: 'card', body),
    ]);
  }
}

/// `<SectionCards />` — one card per sidebar group, generated from
/// [navigation] so it stays in sync automatically.
final class SectionCards extends CustomComponentBase {
  const SectionCards();

  @override
  Pattern get pattern => 'SectionCards';

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) {
    return Component.fragment([
      Document.head(children: [Style(styles: _styles)]),
      div(classes: 'card-grid', attributes: {'data-columns': '3'}, [
        for (final group in navigation)
          a(classes: 'card', href: group.items.first.href, [
            div(classes: 'card-head', [
              span(classes: 'card-icon', [RawText(group.icon)]),
              span(classes: 'card-title', [Component.text(group.title)]),
            ]),
            if (group.summary case final summary?) div(classes: 'card-body', [p([Component.text(summary)])]),
            div(classes: 'card-meta', [
              Component.text('${group.items.length} ${group.items.length == 1 ? 'page' : 'pages'}'),
            ]),
          ]),
      ]),
    ]);
  }
}

/// Icon names accepted by `<Card icon="…">`.
const Map<String, String> _iconsByName = {
  'rocket': NavIcons.rocket,
  'compass': NavIcons.compass,
  'sliders': NavIcons.sliders,
  'table': NavIcons.table,
  'bolt': NavIcons.bolt,
  'shield': NavIcons.shield,
  'key': NavIcons.key,
  'plug': NavIcons.plug,
  'clock': NavIcons.clock,
  'mail': NavIcons.mail,
  'gauge': NavIcons.gauge,
  'dart': NavIcons.dart,
  'terminal': NavIcons.terminal,
  'server': NavIcons.server,
};

List<StyleRule> get _styles => [
  css('.card-grid', [
    css('&').styles(
      display: Display.grid,
      gap: Gap.all(.875.rem),
      margin: Margin.symmetric(vertical: 1.5.rem),
      raw: {'grid-template-columns': 'repeat(1, minmax(0, 1fr))'},
    ),
    css.media(MediaQuery.all(minWidth: 640.px), [
      css('&[data-columns="2"]').styles(raw: {'grid-template-columns': 'repeat(2, minmax(0, 1fr))'}),
      css('&[data-columns="3"]').styles(raw: {'grid-template-columns': 'repeat(2, minmax(0, 1fr))'}),
      css('&[data-columns="4"]').styles(raw: {'grid-template-columns': 'repeat(2, minmax(0, 1fr))'}),
    ]),
    css.media(MediaQuery.all(minWidth: 1024.px), [
      css('&[data-columns="3"]').styles(raw: {'grid-template-columns': 'repeat(3, minmax(0, 1fr))'}),
      css('&[data-columns="4"]').styles(raw: {'grid-template-columns': 'repeat(4, minmax(0, 1fr))'}),
    ]),
  ]),

  css('.card', [
    css('&').styles(
      display: Display.flex,
      flexDirection: FlexDirection.column,
      padding: Padding.symmetric(horizontal: 1.125.rem, vertical: 1.rem),
      radius: BorderRadius.circular(12.px),
      border: Border.all(width: 1.px, color: Color('color-mix(in srgb, currentColor 12%, transparent)')),
      textDecoration: TextDecoration.none,
      color: Color('inherit'),
      transition: Transition('all', duration: 150.ms, curve: Curve.easeInOut),
    ),
    css('&:hover').styles(
      border: Border.all(width: 1.px, color: Color('color-mix(in srgb, currentColor 28%, transparent)')),
      backgroundColor: Color('color-mix(in srgb, currentColor 4%, transparent)'),
      raw: {'transform': 'translateY(-1px)'},
    ),

    css('.card-head', [
      css('&').styles(
        display: Display.flex,
        alignItems: AlignItems.center,
        gap: Gap.column(.5.rem),
      ),
      css('.card-icon').styles(display: Display.flex, color: ContentColors.primary, flex: Flex(shrink: 0)),
      css('.card-title').styles(
        fontWeight: FontWeight.w600,
        fontSize: .9375.rem,
        color: ContentColors.headings,
      ),
      css('.card-badge').styles(
        padding: Padding.symmetric(horizontal: .375.rem),
        radius: BorderRadius.circular(999.px),
        fontSize: .625.rem,
        fontWeight: FontWeight.w700,
        textTransform: TextTransform.upperCase,
        letterSpacing: .03.em,
        color: ContentColors.primary,
        backgroundColor: Color('color-mix(in srgb, currentColor 14%, transparent)'),
      ),
    ]),

    css('.card-body', [
      css('&').styles(fontSize: .875.rem, opacity: .75, margin: Margin.only(top: .375.rem)),
      css('p').styles(margin: Margin.zero),
      css('p + p').styles(margin: Margin.only(top: .5.rem)),
      css('code').styles(fontSize: .8125.rem),
    ]),

    css('.card-meta').styles(
      margin: Margin.only(top: .625.rem),
      fontSize: .6875.rem,
      opacity: .5,
      textTransform: TextTransform.upperCase,
      letterSpacing: .04.em,
    ),
  ]),
];
