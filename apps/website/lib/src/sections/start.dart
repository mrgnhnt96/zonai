/// Quick start plus the agent-tooling pitch, then the closing CTA.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../code.dart';
import '../theme.dart';
import '../ui.dart';

// Uses the same pinned install line as the hero and the download section, so
// there is exactly one place a release URL can go stale.
const _step1 =
    r'$ dart create my_app && cd my_app'
    '\n'
    r'$ dart pub add zonai_schema'
    '\n'
    '\$ $installCommand\n';

const _step2 = r'''
$ ./zonai dev
# no zonai.yaml yet? dev walks you through creating one
''';

const _step3 = r'''
$ ./zonai db migrate generate -n init
$ ./zonai db migrate apply
$ ./zonai serve
''';

const _steps = <(String, String, String)>[
  (
    'Drop in the binary',
    'A Zonai app is an ordinary Dart package. Add the schema library, then put the zonai executable in the project '
        'root — it is not a pub dependency, and it resolves your project relative to where it sits.',
    _step1,
  ),
  (
    'Define tables and start dev',
    'Write your tables under lib/src/schemas/, then start the dev server. It watches worker sources, recompiles them, '
        'and gives you a TUI dashboard.',
    _step2,
  ),
  (
    'Migrate and serve',
    'Generate a migration from your schema, apply it, and the REST API — including the stream routes — is live.',
    _step3,
  ),
];

class QuickStart extends StatelessComponent {
  const QuickStart({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'start',
      eyebrow: 'Quick start',
      title: .fragment([.text('Running in '), accent('a couple of minutes'), .text('.')]),
      lede:
          'Download the binary, define a table, serve. No global install, no Docker, no account. The long version, '
          'with the full schema and rules, is in the docs.',
      children: [
        ol(classes: 'steps', [
          for (final (index, (title, body, code)) in _steps.indexed)
            li(classes: 'step', [
              div(classes: 'step-head', [
                span(classes: 'step-num', [.text('${index + 1}')]),
                div([
                  h3([.text(title)]),
                  p([.text(body)]),
                ]),
              ]),
              div(classes: 'pane step-code', [CodeBlock(code, lang: Lang.shell)]),
            ]),
        ]),

        // The agent pitch — genuinely differentiating, so it gets real estate.
        div(classes: 'agents', [
          div(classes: 'agents-text', [
            div(classes: 'eyebrow', [.text('For coding agents')]),
            h3([.text('Your assistant can read the manual too')]),
            p([
              .text('A curated index for LLMs lives at '),
              a(href: Links.llms, target: .blank, attributes: const {'rel': 'noopener'}, [.text('llms.txt')]),
              .text('. Inside a project, '),
              mono('./zonai ai'),
              .text(
                ' writes framework reference sheets into the repo for Claude Code, Cursor, Copilot, Windsurf, and '
                'Cline — so every developer and every agent shares the same context about how your backend is built.',
              ),
            ]),
          ]),
          div(classes: 'pane agents-code', [
            CodeBlock(
              r'''
$ ./zonai ai all      # every supported tool
$ ./zonai ai claude   # CLAUDE.md
$ ./zonai ai cursor   # .cursor/rules/zonai-*.mdc
''',
              lang: Lang.shell,
            ),
          ]),
        ]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.steps', [
      css('&').styles(
        display: .grid,
        margin: .zero,
        padding: .zero,
        gridTemplate: gridCols(3),
        gap: .all(20.px),
        listStyle: .none,
      ),
      css('.step').styles(display: .flex, flexDirection: .column, gap: .all(14.px), raw: {'min-width': '0'}),
      css('.step-head').styles(display: .flex, gap: .all(13.px)),
      css('.step-num').styles(
        display: .flex,
        width: 27.px,
        height: 27.px,
        border: .all(color: .variable('--edge-2'), width: 1.px),
        radius: .circular(50.percent),
        alignItems: .center,
        justifyContent: .center,
        color: .variable('--zon'),
        fontFamily: .variable('--mono'),
        fontSize: 12.px,
        fontWeight: .w600,
        backgroundColor: .rgba(47, 224, 172, 0.08),
        raw: {'flex': '0 0 auto'},
      ),
      css('.step h3').styles(
        margin: .only(bottom: 6.px),
        color: .variable('--fg'),
        fontSize: 15.px,
        fontWeight: .w600,
      ),
      css('.step p').styles(color: .variable('--fg-mute'), fontSize: 13.5.px, lineHeight: 1.6.em),
      css('.step-code').styles(
        backgroundColor: .variable('--ink'),
        raw: {'margin-top': 'auto'},
      ),
    ]),

    css('.agents', [
      css('&').styles(
        display: .grid,
        margin: .only(top: 52.px),
        padding: .all(30.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(16.px),
        gridTemplate: gridFr([1.35, 1]),
        gap: .all(28.px),
        alignItems: .center,
        raw: {
          'background':
              'radial-gradient(700px 220px at 8% 0%, rgba(169,140,255,0.08), transparent 70%), rgba(255,255,255,0.015)',
        },
      ),
      css('.agents h3').styles(
        margin: .symmetric(vertical: 12.px),
        color: .variable('--fg'),
        fontSize: 24.px,
        fontWeight: .w600,
      ),
      css('.agents p').styles(color: .variable('--fg-dim'), fontSize: 14.5.px, lineHeight: 1.7.em),
      css('.agents-code').styles(backgroundColor: .variable('--ink'), raw: {'min-width': '0'}),
    ]),

    css.media(MediaQuery.screen(maxWidth: 980.px), [
      css('.steps').styles(gridTemplate: gridCols(1)),
      css('.agents').styles(gridTemplate: gridCols(1)),
    ]),
  ];
}

/// The closing call to action.
class FinalCta extends StatelessComponent {
  const FinalCta({super.key});

  @override
  Component build(BuildContext context) {
    return section(classes: 'cta', [
      div(classes: 'wrap cta-inner', [
        const RuneMark(size: 92),
        h2(classes: 'cta-title', [
          .text('Write the backend in the language you '),
          accent('already ship'),
          .text('.'),
        ]),
        p(classes: 'lede cta-lede', [
          .text(
            'Zonai is open source under the MIT license, versioned, and used in production by the people who build '
            'it. Clone it, read it, break it.',
          ),
        ]),
        div(classes: 'cta-buttons', [
          LinkButton(label: 'Get started', href: Links.quickStart, icon: arrowIcon()),
          LinkButton(
            label: 'Browse the source',
            href: Links.github,
            kind: ButtonKind.ghost,
            icon: githubIcon(15),
            external: true,
          ),
        ]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.cta', [
      css('&').styles(
        position: .relative(),
        padding: .symmetric(vertical: 110.px),
        overflow: .hidden,
        textAlign: .center,
      ),
      css('&::before').styles(
        content: '""',
        position: .absolute(top: .zero, left: 50.percent, right: .zero),
        width: 900.px,
        height: 1.px,
        transform: .translate(x: (-50).percent),
        raw: {'background': 'linear-gradient(90deg, transparent, var(--edge-2), transparent)', 'max-width': '100%'},
      ),
      css('.cta-inner').styles(
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        gap: .all(22.px),
      ),
      css('.cta-title').styles(maxWidth: 760.px, fontSize: 44.px, fontWeight: .w700),
      css('.cta-lede').styles(textAlign: .center),
      css('.cta-buttons').styles(display: .flex, flexWrap: .wrap, justifyContent: .center, gap: .all(12.px)),
    ]),
    css.media(MediaQuery.screen(maxWidth: 640.px), [
      css('.cta').styles(padding: .symmetric(vertical: 76.px)),
      css('.cta .cta-title').styles(fontSize: 30.px),
    ]),
  ];
}
