/// The built-in admin dashboard, shown with a real capture of a local project.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../theme.dart';
import '../ui.dart';

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
    return Section(
      id: 'dashboard',
      eyebrow: 'Admin dashboard',
      title: .fragment([.text('A control room you '), accent('did not build'), .text('.')]),
      lede:
          'Every Zonai server serves an admin dashboard at /_. It is compiled in alongside your API, so there is '
          'nothing extra to deploy.',
      children: [
        figure(classes: 'pane dash', [
          img(
            src: '/images/dashboard-tasks.webp',
            alt:
                'The Zonai dashboard open on a tasks table, with seven rows of example data and columns for id, title, '
                'is_complete, created_at and updated_at.',
            width: 1800,
            height: 990,
            loading: MediaLoading.lazy,
          ),
          Component.element(
            tag: 'figcaption',
            children: [.text('The tasks table in the dashboard. Example data from a local test project.')],
          ),
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
        p(classes: 'dash-note', [
          .text('On a new project, add '),
          mono('lib/src/rules/admin_row_rules.dart'),
          .text(' before you sign in. See '),
          a(href: Links.rowRules, [.text('row rules')]),
          .text('.'),
        ]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.dash', [
      css('&').styles(
        margin: .zero,
        backgroundColor: .variable('--ink'),
        raw: {'box-shadow': '0 30px 70px -34px rgba(0,0,0,0.9)'},
      ),
      css('img').styles(display: .block, width: 100.percent, height: .auto),
      css('figcaption').styles(
        padding: .symmetric(vertical: 10.px, horizontal: 16.px),
        color: .variable('--fg-dim'),
        fontSize: 13.px,
        raw: {'border-top': '1px solid var(--edge)'},
      ),
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
      css('.dash-caps').styles(gridTemplate: gridCols(1)),
    ]),
  ];
}
