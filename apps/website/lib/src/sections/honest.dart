/// "What Zonai is not" — lifted almost verbatim from the docs, because the
/// fastest way to lose a developer's trust is to let them find this out later.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../ui.dart';

const _limits = <(String, String)>[
  (
    'Not a full application framework',
    'Zonai is an API server. It renders no HTML and has no view layer. You talk to it from Flutter or Dart with '
        'zonai_client, or over plain HTTP from anything else.',
  ),
  (
    'Not a managed cloud service',
    'There is no dashboard to sign up for and no per-seat bill. You host the binary yourself, anywhere that runs '
        'Linux, macOS, or Windows.',
  ),
  (
    'Not a general-purpose ORM',
    'It is opinionated about how APIs are shaped and it uses SQLite. If you need arbitrary joins across Postgres, '
        'this is the wrong tool and that is fine.',
  ),
  (
    'Not poll-only for live UI',
    'The live path is /db/stream* and client.db.listen. If you find yourself writing a Timer.periodic against a '
        'Zonai backend, you have taken a wrong turn.',
  ),
];

class Honest extends StatelessComponent {
  const Honest({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      classes: 'honest',
      eyebrow: 'Straight answers',
      title: .fragment([.text('What Zonai '), accent('is not'), .text('.')]),
      lede:
          'Every framework has a shape, and pretending otherwise wastes your afternoon. Here is where Zonai stops, so '
          'you can decide before you install anything.',
      children: [
        div(classes: 'honest-grid', [
          for (final (title, body) in _limits)
            div(classes: 'honest-card', [
              span(classes: 'honest-x', [
                svg(
                  width: 13.px,
                  height: 13.px,
                  viewBox: '0 0 16 16',
                  attributes: const {'fill': 'none', 'aria-hidden': 'true'},
                  [
                    path(
                      d: 'M4 4l8 8M12 4l-8 8',
                      attributes: const {'stroke': 'currentColor', 'stroke-width': '2', 'stroke-linecap': 'round'},
                      [],
                    ),
                  ],
                ),
              ]),
              div([
                h3([.text(title)]),
                p([.text(body)]),
              ]),
            ]),
        ]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.honest').styles(
      raw: {
        'background':
            'linear-gradient(180deg, transparent, rgba(255,255,255,0.018) 22%, rgba(255,255,255,0.018) 78%, transparent)',
      },
    ),
    css('.honest-grid', [
      css('&').styles(
        display: .grid,
        gridTemplate: gridCols(2),
        gap: .all(16.px),
      ),
      css('.honest-card').styles(
        display: .flex,
        padding: .all(20.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(14.px),
        gap: .all(14.px),
        backgroundColor: .rgba(255, 255, 255, 0.015),
      ),
      css('.honest-x').styles(
        display: .flex,
        width: 26.px,
        height: 26.px,
        radius: .circular(7.px),
        alignItems: .center,
        justifyContent: .center,
        color: .variable('--rose'),
        backgroundColor: .rgba(255, 122, 107, 0.1),
        raw: {'flex': '0 0 auto', 'margin-top': '2px'},
      ),
      css('.honest-card h3').styles(
        margin: .only(bottom: 7.px),
        color: .variable('--fg'),
        fontSize: 15.px,
        fontWeight: .w600,
      ),
      css('.honest-card p').styles(color: .variable('--fg-mute'), fontSize: 13.5.px, lineHeight: 1.65.em),
    ]),
    css.media(MediaQuery.screen(maxWidth: 860.px), [
      css('.honest-grid').styles(gridTemplate: gridCols(1)),
    ]),
  ];
}
