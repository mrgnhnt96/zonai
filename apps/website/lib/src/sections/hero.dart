/// Hero: the claim, the two CTAs, and the proof — one table definition on the
/// left, the endpoints it produces on the right.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../code.dart';
import '../interactive/install_command.dart';
import '../theme.dart';
import '../ui.dart';

const _schema = r'''
final class TaskTable extends Table<Task> {
  TaskTable(super.$)
    : id = $.id('id', (s) => s.id,
          fromString: TasksId.new, generate: TasksId.generate),
      title = $.text('title', (s) => s.title),
      isComplete = $.boolean('is_complete', (s) => s.isComplete),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  final IdColumn<TasksId> id;
  final TextColumn title;
  final BoolColumn isComplete;
  final CreatedAtColumn createdAt;
  final UpdatedAtColumn updatedAt;
}

final tasks = table('tasks', TaskTable.new);
''';

/// (method, path, what it does, is-a-stream)
const _endpoints = <(String, String, String, bool)>[
  ('POST', '/db', 'create a row', false),
  ('GET', '/db', 'read one', false),
  ('GET', '/db/list', 'query many', false),
  ('GET', '/db/count', 'count matches', false),
  ('PATCH', '/db', 'update', false),
  ('DELETE', '/db', 'delete', false),
  ('GET', '/db/stream', 'live row', true),
  ('GET', '/db/stream/list', 'live list', true),
  ('GET', '/db/stream/count', 'live count', true),
];

class Hero extends StatelessComponent {
  const Hero({super.key});

  @override
  Component build(BuildContext context) {
    return section(classes: 'hero', [
      div(classes: 'wrap', [
        div(classes: 'hero-top', [
          a(
            classes: 'hero-badge',
            href: Links.release,
            target: .blank,
            attributes: const {'rel': 'noopener'},
            [
              span(classes: 'hero-badge-dot', []),
              .text('v$zonaiVersion is out'),
              span(classes: 'hero-badge-sep', []),
              span(classes: 'hero-badge-more', [.text('release notes'), arrowIcon()]),
            ],
          ),

          h1(classes: 'hero-title', [
            .text('Your schema '),
            span(classes: 'hero-em', [.text('is')]),
            .text(' the '),
            accent('API'),
            .text('.'),
          ]),

          p(classes: 'hero-lede', [
            .text(
              'Zonai is a batteries-included backend framework for Dart. Define your tables, write your rules, '
              'and get a complete REST API — auth, live query streams, file uploads, email, and cron — compiled '
              'into a single binary you host yourself.',
            ),
          ]),

          div(classes: 'hero-cta', [
            LinkButton(label: 'Start building', href: Links.quickStart, icon: arrowIcon()),
            LinkButton(
              label: 'Star on GitHub',
              href: Links.github,
              kind: ButtonKind.ghost,
              icon: githubIcon(15),
              external: true,
            ),
          ]),

          const InstallCommand(command: installCommand),

          p(classes: 'hero-fine', [
            .text('macOS · Linux · Windows · one self-extracting binary · '),
            a(href: '#download', [.text('all downloads')]),
          ]),
        ]),

        // Proof: the definition on the left, what it generates on the right.
        div(classes: 'hero-proof', [
          const CodeWindow(
            filename: 'lib/src/schemas/tasks.dart',
            source: _schema,
            badge: 'you write this',
          ),

          div(classes: 'pane endpoints', [
            div(classes: 'window-bar', [
              span(classes: 'endpoints-title', [.text('Generated routes')]),
              span(classes: 'window-badge', [.text('zonai handles this')]),
            ]),
            ul(classes: 'endpoint-list', [
              for (final (index, (method, path, note, stream)) in _endpoints.indexed)
                li(
                  classes: stream ? 'endpoint endpoint-live' : 'endpoint',
                  styles: Styles(raw: {'animation-delay': '${140 + index * 65}ms'}),
                  [
                    span(classes: 'method method-${method.toLowerCase()}', [.text(method)]),
                    code(classes: 'endpoint-path', [.text(path)]),
                    span(classes: 'endpoint-note', [.text(note)]),
                    if (stream) span(classes: 'endpoint-pulse', []),
                  ],
                ),
            ]),
            div(classes: 'endpoints-foot', [
              strong([.text('9 endpoints')]),
              .text(' per table · '),
              strong([.text('0 lines')]),
              .text(' of HTTP code · no codegen step'),
            ]),
          ]),
        ]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.hero', [
      css('&').styles(
        position: .relative(),
        padding: .only(top: 88.px, bottom: 44.px),
        overflow: .hidden,
      ),

      css('.hero-top').styles(
        display: .flex,
        maxWidth: 820.px,
        margin: .symmetric(horizontal: .auto),
        flexDirection: .column,
        alignItems: .center,
        gap: .all(24.px),
        textAlign: .center,
      ),
      // Centred column items are sized by their content and will happily
      // overflow the gutter; cap them at the container width.
      css('.hero-top > *').styles(maxWidth: 100.percent),

      // Badge -------------------------------------------------------------
      css('.hero-badge').styles(
        display: .inlineFlex,
        padding: .symmetric(vertical: 6.px, horizontal: 14.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(999.px),
        transition: Transition('border-color', duration: 160.ms),
        alignItems: .center,
        gap: .all(9.px),
        color: .variable('--fg-dim'),
        fontFamily: .variable('--mono'),
        fontSize: 12.px,
        backgroundColor: .rgba(255, 255, 255, 0.025),
      ),
      css('.hero-badge:hover').styles(color: .variable('--fg'), raw: {'border-color': 'var(--zon-deep)'}),
      css('.hero-badge-dot').styles(
        width: 6.px,
        height: 6.px,
        radius: .circular(50.percent),
        animation: Animation(name: 'pulse-fade', duration: 2.seconds, curve: .easeInOut),
        backgroundColor: .variable('--zon'),
        raw: {'box-shadow': '0 0 8px var(--zon)', 'animation-iteration-count': 'infinite'},
      ),
      css('.hero-badge-sep').styles(width: 1.px, height: 11.px, backgroundColor: .variable('--edge-2')),
      css('.hero-badge-more').styles(
        display: .inlineFlex,
        alignItems: .center,
        gap: .all(5.px),
        color: .variable('--zon'),
      ),
      // Headline ----------------------------------------------------------
      css('.hero-title').styles(
        margin: .only(top: 6.px),
        fontSize: 74.px,
        fontWeight: .w700,
        lineHeight: 1.02.em,
      ),
      css('.hero-em').styles(
        color: .variable('--fg-dim'),
        fontStyle: .italic,
        fontWeight: .w500,
      ),
      css('.hero-lede').styles(
        maxWidth: 660.px,
        color: .variable('--fg-dim'),
        fontSize: 18.px,
        lineHeight: 1.65.em,
      ),

      css('.hero-cta').styles(
        display: .flex,
        margin: .only(top: 6.px),
        flexWrap: .wrap,
        justifyContent: .center,
        gap: .all(12.px),
      ),
      css('.hero-fine').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 12.px,
      ),

      // Proof ---------------------------------------------------------------
      css('.hero-proof').styles(
        display: .grid,
        margin: .only(top: 76.px),
        gridTemplate: gridFr([1.15, 1]),
        gap: .all(20.px),
        alignItems: .start,
      ),
      css('.hero-proof .window').styles(raw: {'min-width': '0'}),

      css('.endpoints').styles(
        display: .flex,
        overflow: .hidden,
        flexDirection: .column,
        backgroundColor: .variable('--ink'),
        raw: {'min-width': '0', 'box-shadow': '0 24px 60px -28px rgba(0,0,0,0.85)'},
      ),
      css('.endpoints-title').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 12.px,
      ),
      css('.endpoint-list').styles(
        margin: .zero,
        padding: .symmetric(vertical: 8.px),
        listStyle: .none,
      ),
      css('.endpoint').styles(
        display: .flex,
        padding: .symmetric(vertical: 7.px, horizontal: 16.px),
        opacity: 0,
        animation: Animation(name: 'endpoint-in', duration: 520.ms, curve: .easeOut, fillMode: .forwards),
        alignItems: .center,
        gap: .all(10.px),
        fontFamily: .variable('--mono'),
        fontSize: 12.5.px,
      ),
      css('.method').styles(
        width: 54.px,
        padding: .symmetric(vertical: 2.px),
        radius: .circular(4.px),
        color: .variable('--fg-mute'),
        textAlign: .center,
        fontSize: 10.px,
        fontWeight: .w600,
        letterSpacing: 0.5.px,
        backgroundColor: .rgba(255, 255, 255, 0.05),
        raw: {'flex': '0 0 auto'},
      ),
      css('.method-get').styles(color: .variable('--sky'), backgroundColor: .rgba(91, 200, 250, 0.12)),
      css('.method-post').styles(color: .variable('--zon'), backgroundColor: .rgba(47, 224, 172, 0.12)),
      css('.method-patch').styles(color: .variable('--gold'), backgroundColor: .rgba(240, 184, 64, 0.12)),
      css('.method-delete').styles(color: .variable('--rose'), backgroundColor: .rgba(255, 122, 107, 0.12)),
      css('.endpoint-path').styles(color: .variable('--fg')),
      css('.endpoint-note').styles(
        color: .variable('--fg-mute'),
        fontSize: 11.5.px,
        raw: {'margin-left': 'auto'},
      ),
      css('.endpoint-live').styles(backgroundColor: .rgba(47, 224, 172, 0.04)),
      css('.endpoint-live .endpoint-path').styles(color: .variable('--zon-soft')),
      css('.endpoint-pulse').styles(
        width: 5.px,
        height: 5.px,
        radius: .circular(50.percent),
        animation: Animation(name: 'pulse-fade', duration: 1600.ms, curve: .easeInOut),
        backgroundColor: .variable('--zon'),
        raw: {'box-shadow': '0 0 7px var(--zon)', 'animation-iteration-count': 'infinite', 'flex': '0 0 auto'},
      ),
      css('.endpoints-foot').styles(
        padding: .symmetric(vertical: 12.px, horizontal: 16.px),
        color: .variable('--fg-mute'),
        fontSize: 12.px,
        backgroundColor: .rgba(255, 255, 255, 0.02),
        raw: {'border-top': '1px solid var(--edge)', 'margin-top': 'auto'},
      ),
      css('.endpoints-foot strong').styles(color: .variable('--fg'), fontWeight: .w600),
    ]),

    // Top level: keyframes cannot be nested inside a selector block.
    css.keyframes('endpoint-in', {
      '0%': Styles(opacity: 0, transform: .translate(x: (-10).px)),
      '100%': Styles(opacity: 1, transform: .translate(x: .zero)),
    }),

    css.media(MediaQuery.screen(maxWidth: 980.px), [
      css('.hero .hero-proof').styles(gridTemplate: gridCols(1)),
      css('.hero .hero-title').styles(fontSize: 52.px),
    ]),
    css.media(MediaQuery.screen(maxWidth: 640.px), [
      css('.hero').styles(
        padding: .only(top: 52.px, bottom: 24.px),
      ),
      css('.hero .hero-title').styles(fontSize: 38.px),
      css('.hero .hero-lede').styles(fontSize: 16.px),
      css('.hero .hero-cta').styles(width: 100.percent, flexDirection: .column),
      css('.hero .hero-cta .btn').styles(justifyContent: .center),
      css('.hero .endpoint-note').styles(display: .none),
    ]),
  ];
}
