/// Site footer.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../theme.dart';
import '../ui.dart';

const _columns = <(String, List<(String, String)>)>[
  ('Docs', [
    ('Introduction', Links.docs),
    ('Quick start', Links.quickStart),
    ('Live queries', Links.streaming),
    ('Request pipeline', Links.pipeline),
    ('Deployment', Links.deployment),
  ]),
  ('Download', [
    ('Get the CLI', '/#download'),
    ('Latest release (v$zonaiVersion)', Links.release),
    ('All releases', Links.allReleases),
    ('Install guide', Links.installation),
  ]),
  ('Packages', [
    ('zonai_client', Links.pubClient),
    ('zonai_schema', Links.pubSchema),
  ]),
  ('Project', [
    ('GitHub', Links.github),
    ('Issues', Links.issues),
    ('llms.txt', Links.llms),
  ]),
];

class SiteFooter extends StatelessComponent {
  const SiteFooter({super.key});

  @override
  Component build(BuildContext context) {
    return footer(classes: 'foot', [
      div(classes: 'wrap foot-inner', [
        div(classes: 'foot-brand', [
          div(classes: 'foot-mark', [
            const RuneMark(size: 30, glow: false),
            span(classes: 'brand-name', [.text('zonai')]),
          ]),
          p([.text('A batteries-included Dart backend framework. Self-hosted, compiled, and yours.')]),
          span(classes: 'foot-ver', [.text('v$zonaiVersion · MIT')]),
        ]),

        div(classes: 'foot-cols', [
          for (final (heading, links) in _columns)
            nav(classes: 'foot-col', attributes: {'aria-label': heading}, [
              h4([.text(heading)]),
              for (final (label, href) in links)
                // Same-page anchors stay in this tab; everything else leaves.
                if (href.startsWith('/'))
                  a(href: href, [.text(label)])
                else
                  a(href: href, target: .blank, attributes: const {'rel': 'noopener'}, [.text(label)]),
            ]),
        ]),
      ]),

      div(classes: 'wrap foot-base', [
        span([.text('© 2026 Zonai contributors')]),
        span(classes: 'foot-built', [
          .text('Built with '),
          a(href: 'https://jaspr.site', target: .blank, attributes: const {'rel': 'noopener'}, [.text('Jaspr')]),
          .text(' — this page is Dart too.'),
        ]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.foot', [
      css('&').styles(
        padding: .only(top: 56.px, bottom: 28.px),
        backgroundColor: .rgba(255, 255, 255, 0.012),
        raw: {'border-top': '1px solid var(--edge)'},
      ),
      css('.foot-inner').styles(
        display: .grid,
        gridTemplate: gridFr([1.2, 2]),
        gap: .all(40.px),
      ),
      css('.foot-brand').styles(display: .flex, maxWidth: 300.px, flexDirection: .column, gap: .all(12.px)),
      css('.foot-mark').styles(display: .flex, alignItems: .center, gap: .all(9.px)),
      css('.foot-brand .brand-name').styles(
        color: .variable('--fg'),
        fontFamily: .variable('--sans'),
        fontSize: 18.px,
        fontWeight: .w700,
      ),
      css('.foot-brand p').styles(color: .variable('--fg-mute'), fontSize: 13.5.px, lineHeight: 1.65.em),
      css('.foot-ver').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 11.px,
      ),

      css('.foot-cols').styles(
        display: .grid,
        gridTemplate: gridCols(4),
        gap: .all(24.px),
      ),
      css('.foot-col').styles(display: .flex, flexDirection: .column, gap: .all(9.px)),
      css('.foot-col h4').styles(
        margin: .only(bottom: 3.px),
        color: .variable('--fg'),
        fontSize: 12.px,
        fontWeight: .w600,
        textTransform: .upperCase,
        letterSpacing: 1.px,
      ),
      css('.foot-col a').styles(color: .variable('--fg-mute'), fontSize: 13.5.px),
      css('.foot-col a:hover').styles(color: .variable('--zon')),

      css('.foot-base').styles(
        display: .flex,
        margin: .only(top: 44.px),
        padding: .only(top: 20.px),
        flexWrap: .wrap,
        justifyContent: .spaceBetween,
        gap: .all(12.px),
        color: .variable('--fg-mute'),
        fontSize: 12.5.px,
        raw: {'border-top': '1px solid var(--edge)'},
      ),
    ]),
    css.media(MediaQuery.screen(maxWidth: 860.px), [
      css('.foot .foot-inner').styles(gridTemplate: gridCols(1)),
    ]),
    css.media(MediaQuery.screen(maxWidth: 560.px), [
      css('.foot .foot-cols').styles(gridTemplate: gridCols(2)),
    ]),
  ];
}
