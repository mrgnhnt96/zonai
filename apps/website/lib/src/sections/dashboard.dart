/// The built-in admin dashboard.
///
/// The mock below is an illustration, not a live connection — it is labelled as
/// a preview on the page so nobody reads the numbers as real.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../ui.dart';

/// Requests per hour over 24h. A single series, so magnitude is encoded by bar
/// height only — every bar takes the same hue rather than double-encoding.
const _buckets = <int>[
  18,
  12,
  9,
  7,
  6,
  8,
  14,
  26,
  41,
  58,
  67,
  72,
  69,
  74,
  81,
  77,
  63,
  55,
  48,
  39,
  33,
  28,
  24,
  21,
];

/// (label, value, tone) — `tone` picks a reserved status color where it means
/// something, and stays null where the number is just a number.
const _tiles = <(String, String, String?)>[
  ('Requests · 24h', '1,043', null),
  ('Errors · 24h', '7', 'bad'),
  ('Active sessions', '38', null),
  ('p95 response', '24 ms', 'good'),
];

const _capabilities = <(String, String)>[
  (
    'Browse and edit every table',
    'Your schema rendered as a data grid — inline edit, row detail, search and filter (including datetime ranges), '
        'foreign-key pickers, and photo columns that show the actual image.',
  ),
  (
    'Watch the traffic',
    'Requests and errors over the last 24 hours, active sessions, p95 response time, and per-table row counts. '
        'Admin traffic can be excluded so your own clicking does not skew it.',
  ),
  (
    'Keep an eye on jobs',
    'Which cron jobs exist, which are running right now, and the errors coming up most often — without opening a '
        'terminal or tailing a log.',
  ),
  (
    'Exercise the auth flows',
    'Sign-in, one-time passcodes, magic links, password reset and email verification are all real screens, so you '
        'can try the flow you just configured.',
  ),
];

class AdminDashboard extends StatelessComponent {
  const AdminDashboard({super.key});

  @override
  Component build(BuildContext context) {
    final peak = _buckets.reduce((a, b) => a > b ? a : b);

    return Section(
      id: 'dashboard',
      eyebrow: 'Admin dashboard',
      title: .fragment([.text('A control room you '), accent('did not build'), .text('.')]),
      lede:
          'Every Zonai server serves an admin dashboard at /_ — a data browser, live metrics, cron status and the '
          'full auth flow. It is compiled into the same binary as your API, so there is nothing extra to deploy, '
          'host, or keep in sync.',
      children: [
        div(classes: 'pane dash', [
          // Browser chrome, so it reads as a running app rather than a diagram.
          div(classes: 'window-bar dash-bar', [
            span(classes: 'dots', [span([]), span([]), span([])]),
            span(classes: 'dash-url', [.text('localhost:8080/_')]),
            span(classes: 'window-badge', [.text('preview')]),
          ]),

          div(classes: 'dash-body', [
            div(classes: 'dash-tiles', [
              for (final (label, value, tone) in _tiles)
                div(classes: 'tile', [
                  span(classes: 'tile-label', [.text(label)]),
                  span(classes: 'tile-value', [.text(value)]),
                  if (tone != null)
                    span(classes: 'tile-tag tile-tag-$tone', [
                      .text(tone == 'bad' ? '0.7% of requests' : 'within budget'),
                    ]),
                ]),
            ]),

            figure(classes: 'chart', [
              .element(
                tag: 'figcaption',
                classes: 'chart-title',
                children: [
                  span([.text('Requests per hour')]),
                  span(classes: 'chart-sub', [.text('last 24 hours')]),
                ],
              ),
              div(
                classes: 'chart-plot',
                attributes: const {
                  'role': 'img',
                  'aria-label':
                      'Requests per hour over the last 24 hours, rising through the morning to a peak of '
                      '81 around midday, then tapering off overnight.',
                },
                [
                  for (final count in _buckets)
                    span(
                      classes: 'bar',
                      styles: Styles(raw: {'height': '${(count / peak * 100).round()}%'}),
                      [],
                    ),
                ],
              ),
              div(classes: 'chart-axis', [
                span([.text('00:00')]),
                span([.text('12:00')]),
                span([.text('23:00')]),
              ]),
            ]),

            // A slice of the table browser.
            div(classes: 'dash-table', [
              div(classes: 'dash-table-head', [
                span([.text('tasks')]),
                span(classes: 'dash-chip', [.text('1,204 rows')]),
              ]),
              ul(classes: 'dash-rows', [
                for (final (id, title, done) in const [
                  ('tk_9f2a', 'Ship the migration', false),
                  ('tk_4c81', 'Review auth rules', false),
                  ('tk_7b30', 'Wire up SMTP', true),
                ])
                  li([
                    code([.text(id)]),
                    span(classes: 'dash-title', [.text(title)]),
                    span(classes: done ? 'dash-bool dash-bool-on' : 'dash-bool', [.text('$done')]),
                  ]),
              ]),
            ]),
          ]),
        ]),

        div(classes: 'dash-caps', [
          for (final (title, body) in _capabilities)
            div(classes: 'dash-cap', [
              h3([.text(title)]),
              p([.text(body)]),
            ]),
        ]),

        p(classes: 'dash-note', [
          .text('Built with Jaspr, same as this page. Metrics come from '),
          mono('GET /dashboard/metrics'),
          .text(', so anything the dashboard shows you can also pull yourself.'),
        ]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.dash', [
      css('&').styles(backgroundColor: .variable('--ink'), raw: {'box-shadow': '0 30px 70px -34px rgba(0,0,0,0.9)'}),
      css('.dash-url').styles(
        padding: .symmetric(vertical: 3.px, horizontal: 10.px),
        radius: .circular(6.px),
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 11.5.px,
        backgroundColor: .rgba(255, 255, 255, 0.04),
      ),
      css('.dash-body').styles(
        display: .flex,
        padding: .all(20.px),
        flexDirection: .column,
        gap: .all(18.px),
      ),

      // Stat tiles ---------------------------------------------------------
      css('.dash-tiles').styles(display: .grid, gridTemplate: gridCols(4), gap: .all(12.px)),
      css('.tile').styles(
        display: .flex,
        padding: .all(14.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(10.px),
        flexDirection: .column,
        gap: .all(5.px),
        backgroundColor: .rgba(255, 255, 255, 0.02),
      ),
      css('.tile-label').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 10.5.px,
        textTransform: .upperCase,
        letterSpacing: 0.7.px,
      ),
      // Values wear a text token, never a series color.
      css('.tile-value').styles(
        color: .variable('--fg'),
        fontFamily: .variable('--sans'),
        fontSize: 26.px,
        fontWeight: .w600,
        letterSpacing: (-0.5).px,
      ),
      css('.tile-tag').styles(
        alignSelf: .start,
        padding: .symmetric(vertical: 1.px, horizontal: 7.px),
        radius: .circular(999.px),
        fontFamily: .variable('--mono'),
        fontSize: 10.px,
      ),
      // Reserved status colors, each carrying a label rather than color alone.
      css('.tile-tag-bad').styles(color: .variable('--rose'), backgroundColor: .rgba(255, 122, 107, 0.12)),
      css('.tile-tag-good').styles(color: .variable('--zon'), backgroundColor: .rgba(47, 224, 172, 0.12)),

      // Chart ----------------------------------------------------------------
      css('.chart').styles(
        margin: .zero,
        padding: .all(16.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(10.px),
        backgroundColor: .rgba(255, 255, 255, 0.015),
      ),
      css('.chart-title').styles(
        display: .flex,
        margin: .only(bottom: 14.px),
        alignItems: .baseline,
        gap: .all(9.px),
        color: .variable('--fg'),
        fontFamily: .variable('--sans'),
        fontSize: 13.px,
        fontWeight: .w600,
      ),
      css('.chart-sub').styles(color: .variable('--fg-mute'), fontSize: 11.px, fontWeight: .w400),
      css('.chart-plot').styles(
        display: .flex,
        height: 96.px,
        // A 2px surface gap between adjacent bars.
        gap: .all(2.px),
        alignItems: .end,
      ),
      css('.bar').styles(
        // Rounded data-end, square against the baseline.
        radius: .only(topLeft: .circular(4.px), topRight: .circular(4.px)),
        backgroundColor: .variable('--zon'),
        raw: {'flex': '1 1 0', 'min-width': '0', 'opacity': '0.85'},
      ),
      css('.chart-axis').styles(
        display: .flex,
        margin: .only(top: 8.px),
        justifyContent: .spaceBetween,
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 10.px,
      ),

      // Table strip -----------------------------------------------------------
      css('.dash-table').styles(
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(10.px),
        overflow: .hidden,
      ),
      css('.dash-table-head').styles(
        display: .flex,
        padding: .symmetric(vertical: 9.px, horizontal: 14.px),
        alignItems: .center,
        gap: .all(10.px),
        color: .variable('--fg'),
        fontFamily: .variable('--mono'),
        fontSize: 12.px,
        backgroundColor: .rgba(255, 255, 255, 0.03),
      ),
      css('.dash-chip').styles(
        color: .variable('--fg-mute'),
        fontSize: 10.5.px,
        raw: {'margin-left': 'auto'},
      ),
      css('.dash-rows').styles(margin: .zero, padding: .zero, listStyle: .none),
      css('.dash-rows li').styles(
        display: .flex,
        padding: .symmetric(vertical: 9.px, horizontal: 14.px),
        alignItems: .center,
        gap: .all(12.px),
        fontSize: 12.5.px,
        raw: {'border-top': '1px solid var(--edge)'},
      ),
      css('.dash-rows code').styles(color: .variable('--fg-mute'), fontSize: 11.px),
      css('.dash-title').styles(color: .variable('--fg-dim'), raw: {'flex': '1 1 auto'}),
      css('.dash-bool').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 11.px,
      ),
      css('.dash-bool-on').styles(color: .variable('--zon')),
    ]),

    css('.dash-caps', [
      css('&').styles(
        display: .grid,
        margin: .only(top: 32.px),
        gridTemplate: gridCols(4),
        gap: .all(24.px),
      ),
      css('.dash-cap').styles(
        padding: .only(left: 15.px),
        raw: {'border-left': '2px solid var(--edge-2)'},
      ),
      css('.dash-cap h3').styles(
        margin: .only(bottom: 8.px),
        color: .variable('--fg'),
        fontSize: 14.5.px,
        fontWeight: .w600,
      ),
      css('.dash-cap p').styles(color: .variable('--fg-mute'), fontSize: 13.px, lineHeight: 1.6.em),
    ]),

    css('.dash-note').styles(
      margin: .only(top: 26.px),
      color: .variable('--fg-mute'),
      fontSize: 13.px,
      lineHeight: 1.8.em,
    ),

    css.media(MediaQuery.screen(maxWidth: 980.px), [
      css('.dash-caps').styles(gridTemplate: gridCols(2)),
    ]),
    css.media(MediaQuery.screen(maxWidth: 640.px), [
      css('.dash .dash-tiles').styles(gridTemplate: gridCols(2)),
      css('.dash-caps').styles(gridTemplate: gridCols(1)),
    ]),
  ];
}
