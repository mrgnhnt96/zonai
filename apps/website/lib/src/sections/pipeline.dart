/// How a request is processed — the ordered pipeline, with an energy pulse
/// running along it. Pure CSS: no JS needed for the animation.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../theme.dart';
import '../ui.dart';

/// (label, where it runs, one-line description)
const _stages = <(String, String, String)>[
  ('Rate Limit', 'worker', 'Per-IP policy, per table and operation.'),
  ('Rules', 'in-process', 'Returns true or false. A no is a 403 before any SQL.'),
  ('Operations', 'in-process', 'Your business logic, linked into the binary.'),
  ('SQLite', 'engine', 'The query actually executes.'),
  ('Extensions', 'worker', 'Lifecycle hooks and side effects: email, mutations, fan-out.'),
];

class Pipeline extends StatelessComponent {
  const Pipeline({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'pipeline',
      eyebrow: 'How it works',
      title: .fragment([.text('Compiled Dart, '), accent('all the way down'), .text('.')]),
      lede:
          'There is no interpreter on the request path. Your operations and rules are linked into the server binary; '
          'config, extensions, rate limits, and crons compile into separate workers. Every request walks the same '
          'ordered pipeline.',
      children: [
        div(classes: 'pipe', [
          div(classes: 'pipe-node pipe-edge', [
            span(classes: 'pipe-name', [.text('HTTP Request')]),
          ]),

          for (final (index, (name, where, note)) in _stages.indexed) ...[
            div(classes: 'pipe-arrow', [
              span(classes: 'pipe-line', []),
              span(
                classes: 'pipe-spark',
                styles: Styles(raw: {'animation-delay': '${index * 380}ms'}),
                [],
              ),
            ]),
            div(classes: 'pipe-node', [
              span(classes: 'pipe-name', [.text(name)]),
              span(classes: 'pipe-where pipe-where-$where', [.text(where)]),
              span(classes: 'pipe-note', [.text(note)]),
            ]),
          ],

          div(classes: 'pipe-arrow', [
            span(classes: 'pipe-line', []),
            span(
              classes: 'pipe-spark',
              styles: Styles(raw: {'animation-delay': '1900ms'}),
              [],
            ),
          ]),
          div(classes: 'pipe-node pipe-edge', [
            span(classes: 'pipe-name', [.text('Response')]),
          ]),
        ]),

        div(classes: 'pipe-callouts', [
          div(classes: 'pipe-callout pipe-callout-deny', [
            span(classes: 'pipe-code', [.text('403')]),
            div([
              h3([.text('Denied requests never touch the database')]),
              p([
                .text('Rules run '),
                strong([.text('before')]),
                .text(
                  ' any SQL is executed. If a rule returns false the request is rejected immediately, with zero '
                  'database access and nothing to roll back.',
                ),
              ]),
            ]),
          ]),
          div(classes: 'pipe-callout', [
            span(classes: 'pipe-code pipe-code-ok', [.text('AOT')]),
            div([
              h3([.text('One binary to ship')]),
              p([
                .text('./zonai build produces '),
                mono('build/zonai'),
                .text(
                  ' with your project linked in for the CRUD hot path. Copy it to a server and run it — no runtime '
                  'dependencies, no Dart SDK on the box.',
                ),
              ]),
            ]),
          ]),
        ]),

        docsLink('Walk through the full pipeline', Links.pipeline),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.pipe', [
      css('&').styles(
        display: .flex,
        padding: .symmetric(vertical: 34.px, horizontal: 22.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(16.px),
        overflow: .only(x: .auto),
        alignItems: .stretch,
        backgroundColor: .rgba(255, 255, 255, 0.015),
      ),

      css('.pipe-node').styles(
        display: .flex,
        minWidth: 150.px,
        padding: .symmetric(vertical: 16.px, horizontal: 14.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(12.px),
        transition: Transition('border-color', duration: 200.ms),
        flexDirection: .column,
        gap: .all(7.px),
        backgroundColor: .variable('--slab'),
        raw: {'flex': '1 1 0'},
      ),
      css('.pipe-node:hover').styles(raw: {'border-color': 'var(--zon-deep)'}),
      css('.pipe-edge').styles(
        minWidth: 108.px,
        justifyContent: .center,
        backgroundColor: .rgba(255, 255, 255, 0.02),
        raw: {'flex': '0 0 auto', 'border-style': 'dashed'},
      ),
      css('.pipe-name').styles(
        color: .variable('--fg'),
        fontFamily: .variable('--sans'),
        fontSize: 14.px,
        fontWeight: .w600,
      ),
      css('.pipe-where').styles(
        alignSelf: .start,
        padding: .symmetric(vertical: 1.px, horizontal: 7.px),
        radius: .circular(999.px),
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 10.px,
        backgroundColor: .rgba(255, 255, 255, 0.05),
      ),
      css('.pipe-where-in-process').styles(color: .variable('--zon'), backgroundColor: .rgba(47, 224, 172, 0.1)),
      css('.pipe-where-engine').styles(color: .variable('--gold'), backgroundColor: .rgba(240, 184, 64, 0.1)),
      css('.pipe-note').styles(color: .variable('--fg-mute'), fontSize: 12.px, lineHeight: 1.5.em),

      // Connector with a travelling spark.
      css('.pipe-arrow').styles(
        display: .flex,
        position: .relative(),
        width: 34.px,
        alignItems: .center,
        raw: {'flex': '0 0 auto'},
      ),
      css('.pipe-line').styles(
        width: 100.percent,
        height: 1.px,
        backgroundColor: .variable('--edge-2'),
      ),
      css('.pipe-spark').styles(
        position: .absolute(left: .zero),
        width: 6.px,
        height: 6.px,
        radius: .circular(50.percent),
        animation: Animation(name: 'pipe-travel', duration: 2400.ms, curve: .easeInOut),
        backgroundColor: .variable('--zon'),
        raw: {'box-shadow': '0 0 10px 2px var(--zon-glow)', 'animation-iteration-count': 'infinite'},
      ),
    ]),

    // Top level: keyframes cannot be nested inside a selector or media block.
    css.keyframes('pipe-travel', {
      '0%': Styles(opacity: 0, transform: .translate(x: .zero)),
      '18%': Styles(opacity: 1),
      '82%': Styles(opacity: 1),
      '100%': Styles(opacity: 0, transform: .translate(x: 30.px)),
    }),
    css.keyframes('pipe-travel-y', {
      '0%': Styles(opacity: 0, transform: .translate(y: .zero)),
      '18%': Styles(opacity: 1),
      '82%': Styles(opacity: 1),
      '100%': Styles(opacity: 0, transform: .translate(y: 22.px)),
    }),

    css('.pipe-callouts', [
      css('&').styles(
        display: .grid,
        margin: .only(top: 24.px, bottom: 32.px),
        gridTemplate: gridCols(2),
        gap: .all(16.px),
      ),
      css('.pipe-callout').styles(
        display: .flex,
        padding: .all(20.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(14.px),
        gap: .all(16.px),
        backgroundColor: .rgba(255, 255, 255, 0.015),
      ),
      css('.pipe-callout h3').styles(
        margin: .only(bottom: 7.px),
        color: .variable('--fg'),
        fontSize: 15.px,
        fontWeight: .w600,
      ),
      css('.pipe-callout p').styles(color: .variable('--fg-mute'), fontSize: 14.px, lineHeight: 1.6.em),
      css('.pipe-callout strong').styles(color: .variable('--fg-dim')),
      css('.pipe-code').styles(
        display: .flex,
        width: 46.px,
        height: 30.px,
        radius: .circular(7.px),
        alignItems: .center,
        justifyContent: .center,
        color: .variable('--rose'),
        fontFamily: .variable('--mono'),
        fontSize: 12.px,
        fontWeight: .w600,
        backgroundColor: .rgba(255, 122, 107, 0.12),
        raw: {'flex': '0 0 auto'},
      ),
      css('.pipe-code-ok').styles(color: .variable('--zon'), backgroundColor: .rgba(47, 224, 172, 0.12)),
    ]),

    css.media(MediaQuery.screen(maxWidth: 980.px), [
      css('.pipe-callouts').styles(gridTemplate: gridCols(1)),
    ]),
    css.media(MediaQuery.screen(maxWidth: 760.px), [
      // Stack the pipeline vertically; the sparks now travel downward.
      css('.pipe').styles(flexDirection: .column, alignItems: .stretch, gap: .all(0.px)),
      css('.pipe .pipe-arrow').styles(width: 100.percent, height: 26.px, justifyContent: .center),
      css('.pipe .pipe-line').styles(width: 1.px, height: 100.percent),
      css('.pipe .pipe-spark').styles(
        position: .absolute(top: .zero, left: .auto),
        animation: Animation(name: 'pipe-travel-y', duration: 2400.ms, curve: .easeInOut),
        raw: {'animation-iteration-count': 'infinite'},
      ),
    ]),
  ];
}
