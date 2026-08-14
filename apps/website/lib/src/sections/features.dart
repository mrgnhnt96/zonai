/// The feature grid — everything that ships in the box.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../theme.dart';
import '../ui.dart';

/// A single card. [glyph] is drawn from a small set of hand-rolled SVG paths so
/// the page pulls in no icon font.
typedef Feature = ({String icon, String title, String body, String? link});

const _features = <Feature>[
  (
    icon: 'routes',
    title: 'A REST API per table',
    body:
        'Create, read, list, count, update, delete and three live-stream routes, handled straight from your schema. '
        'No handler code and no generation step.',
    link: null,
  ),
  (
    icon: 'key',
    title: 'Authentication included',
    body:
        'Password sign-up/sign-in, one-time passcodes, and magic links — each a single trait mixed into an auth '
        'table. Sessions, refresh, and logout come with it.',
    link: Links.docs,
  ),
  (
    icon: 'shield',
    title: 'Rules before SQL',
    body:
        'Table and row rules are plain Dart returning true or false. They run ahead of the query, so a denial costs '
        'a 403 and nothing else.',
    link: Links.rules,
  ),
  (
    icon: 'stream',
    title: 'Live query streams',
    body:
        'GET /db/stream, /db/stream/list and /db/stream/count push new payloads as SQLite changes. In Dart, that is '
        'client.db.listen.',
    link: Links.streaming,
  ),
  (
    icon: 'gauge',
    title: 'Built-in admin dashboard',
    body:
        'Served at /_ from the same binary: browse and edit every table, watch requests and errors, check cron '
        'status, and run the auth flows. Nothing extra to deploy.',
    link: null,
  ),
  (
    icon: 'dart',
    title: 'Generated Dart client',
    body:
        'zonai_client wraps auth, admin auth, db, photos, and email so your Flutter app never hand-rolls an HTTP '
        'call or a JSON map.',
    link: Links.client,
  ),
  (
    icon: 'mail',
    title: 'Transactional email',
    body:
        'SMTP-backed HTML templates with Mustache variables, sent from lifecycle hooks. Built-in templates for the '
        'auth flows, custom ones for everything else.',
    link: null,
  ),
  (
    icon: 'clock',
    title: 'Scheduled jobs',
    body:
        'Cron-syntax jobs compiled into their own worker, with the full database API and catch-up logic for runs '
        'missed while the server was down.',
    link: null,
  ),
  (
    icon: 'gauge',
    title: 'Per-IP rate limiting',
    body:
        'A policy class per table and operation, with dedicated buckets for the auth routes and trusted-proxy '
        'handling for real client IPs.',
    link: null,
  ),
  (
    icon: 'box',
    title: 'One binary to deploy',
    body:
        './zonai build links your project into build/zonai. Cross-compile it, copy it to a host, run it. SQLite is '
        'bundled; nothing else is required.',
    link: Links.deployment,
  ),
];

/// Icon paths, drawn on a 24×24 grid, stroked with currentColor.
const _glyphs = <String, String>{
  'routes': 'M4 7h6m4 0h6M4 12h16M4 17h6m4 0h6',
  'key': 'M14.5 9.5a3.5 3.5 0 1 0-3.4 3.5L8 16v2h2l1-1h2l1-1v-2l1.2-1.2a3.5 3.5 0 0 0-.7-3.3ZM16 7.5h.01',
  'shield': 'M12 3.5 5 6.2v5c0 4.2 2.9 7.6 7 9.3 4.1-1.7 7-5.1 7-9.3v-5L12 3.5ZM9.3 12l1.9 2 3.5-3.8',
  'stream': 'M4 8h5m6 0h5M4 16h9m4 0h3M4 12h3m4 0h9M6 8v0M13 16v0',
  'dart': 'M6 6h8l6 6-6 6H6V6Zm2.5 4.5 3.5 3.5m0-3.5-3.5 3.5',
  'mail': 'M3.5 7.5h17v10h-17v-10Zm0 .5 8.5 6 8.5-6',
  'clock': 'M12 4.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15ZM12 8v4.3l3 1.8',
  'gauge': 'M4.5 17a8 8 0 1 1 15 0M12 13.5l3.5-3.5M12 13.5v0',
  'box': 'M12 3.5 20 8v8l-8 4.5L4 16V8l8-4.5Zm0 0v17M4 8l8 4.5L20 8',
};

Component _icon(String name) => svg(
  width: 20.px,
  height: 20.px,
  viewBox: '0 0 24 24',
  attributes: const {'fill': 'none', 'aria-hidden': 'true'},
  [
    path(
      d: _glyphs[name]!,
      attributes: const {
        'stroke': 'currentColor',
        'stroke-width': '1.5',
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
      },
      [],
    ),
  ],
);

/// Cards with a `link` become anchors; the rest stay plain `div`s so screen
/// readers are not told about a destination that does not exist.
final class _FeatureCard extends StatelessComponent {
  const _FeatureCard(this.feature);

  final Feature feature;

  @override
  Component build(BuildContext context) {
    final content = [
      span(classes: 'feat-icon', [_icon(feature.icon)]),
      h3(classes: 'feat-title', [.text(feature.title)]),
      p(classes: 'feat-body', [.text(feature.body)]),
      if (feature.link != null) span(classes: 'feat-more', [.text('Docs'), arrowIcon()]),
    ];

    return switch (feature.link) {
      final href? => a(
        classes: 'feat',
        href: href,
        target: .blank,
        attributes: const {'rel': 'noopener'},
        content,
      ),
      null => div(classes: 'feat', content),
    };
  }
}

class Features extends StatelessComponent {
  const Features({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'features',
      eyebrow: 'In the box',
      title: .fragment([.text('The parts you would have '), accent('written anyway'), .text('.')]),
      lede:
          'Zonai is opinionated so the boring half of a backend is already decided. Everything below is part of the '
          'framework, not a plugin you go shopping for.',
      children: [
        div(classes: 'feat-grid', [
          for (final feature in _features) _FeatureCard(feature),
        ]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.feat-grid').styles(
      display: .grid,
      gridTemplate: gridCols(3),
      gap: .all(16.px),
    ),

    css('.feat', [
      css('&').styles(
        display: .flex,
        position: .relative(),
        padding: .all(22.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(14.px),
        overflow: .hidden,
        transition: Transition.combine([
          Transition('border-color', duration: 200.ms),
          Transition('transform', duration: 200.ms, curve: .easeOut),
          Transition('background-color', duration: 200.ms),
        ]),
        flexDirection: .column,
        gap: .all(12.px),
        color: .inherit,
        backgroundColor: .rgba(255, 255, 255, 0.015),
      ),
      css('&:hover').styles(
        transform: .translate(y: (-3).px),
        backgroundColor: .rgba(255, 255, 255, 0.03),
        raw: {'border-color': 'var(--edge-2)'},
      ),
      // A faint wash of energy that only appears on hover.
      css('&::after').styles(
        content: '""',
        position: .absolute(top: .zero, left: .zero, right: .zero),
        height: 1.px,
        opacity: 0,
        transition: Transition('opacity', duration: 200.ms),
        raw: {'background': 'linear-gradient(90deg, transparent, var(--zon), transparent)'},
      ),
      css('&:hover::after').styles(opacity: 0.7),

      css('.feat-icon').styles(
        display: .flex,
        width: 38.px,
        height: 38.px,
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(10.px),
        alignItems: .center,
        justifyContent: .center,
        color: .variable('--zon'),
        backgroundColor: .rgba(47, 224, 172, 0.07),
      ),
      css('.feat-title').styles(
        color: .variable('--fg'),
        fontSize: 16.px,
        fontWeight: .w600,
      ),
      css('.feat-body').styles(
        color: .variable('--fg-mute'),
        fontSize: 13.5.px,
        lineHeight: 1.65.em,
      ),
      css('.feat-more').styles(
        display: .inlineFlex,
        transition: Transition('gap', duration: 200.ms),
        alignItems: .center,
        gap: .all(6.px),
        color: .variable('--zon'),
        fontFamily: .variable('--sans'),
        fontSize: 13.px,
        fontWeight: .w600,
        raw: {'margin-top': 'auto', 'padding-top': '4px'},
      ),
      css('&:hover .feat-more').styles(gap: .all(10.px)),
    ]),

    css.media(MediaQuery.screen(maxWidth: 980.px), [
      css('.feat-grid').styles(gridTemplate: gridCols(2)),
    ]),
    css.media(MediaQuery.screen(maxWidth: 640.px), [
      css('.feat-grid').styles(gridTemplate: gridCols(1)),
    ]),
  ];
}
