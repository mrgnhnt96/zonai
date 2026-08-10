/// Small shared building blocks: buttons, the rune mark, section scaffolding.
library;

import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

import 'theme.dart';

/// Visual weight of a [LinkButton].
enum ButtonKind { primary, ghost, quiet }

/// The site's only button. It is always a link — nothing here submits a form.
class LinkButton extends StatelessComponent {
  const LinkButton({
    required this.label,
    required this.href,
    this.kind = ButtonKind.primary,
    this.icon,
    this.external = false,
    super.key,
  });

  final String label;
  final String href;
  final ButtonKind kind;
  final Component? icon;
  final bool external;

  @override
  Component build(BuildContext context) {
    return a(
      classes: 'btn btn-${kind.name}',
      href: href,
      target: external ? .blank : null,
      attributes: external ? const {'rel': 'noopener'} : null,
      [
        span(classes: 'btn-label', [.text(label)]),
        if (icon case final glyph?) span(classes: 'btn-icon', [glyph]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.btn', [
      css('&').styles(
        display: .inlineFlex,
        padding: .symmetric(vertical: 11.px, horizontal: 20.px),
        border: .all(color: Colors.transparent, width: 1.px),
        radius: .circular(10.px),
        cursor: .pointer,
        userSelect: .none,
        transition: Transition.combine([
          Transition('transform', duration: 160.ms, curve: .easeOut),
          Transition('box-shadow', duration: 160.ms),
          Transition('background-color', duration: 160.ms),
          Transition('border-color', duration: 160.ms),
          Transition('color', duration: 160.ms),
        ]),
        alignItems: .center,
        gap: .all(9.px),
        fontFamily: .variable('--sans'),
        fontSize: 14.5.px,
        fontWeight: .w600,
        textDecoration: .none,
        whiteSpace: .noWrap,
      ),
      css('&:hover').styles(transform: .translate(y: (-2).px)),
      css('&:active').styles(transform: .translate(y: .zero)),
      css('.btn-icon').styles(
        display: .inlineFlex,
        transition: Transition('transform', duration: 160.ms, curve: .easeOut),
        alignItems: .center,
      ),
      css('&:hover .btn-icon').styles(transform: .translate(x: 3.px)),
    ]),

    css('.btn-primary', [
      css('&').styles(
        color: .variable('--void'),
        backgroundColor: .variable('--zon'),
        raw: {
          'background-image': 'linear-gradient(180deg, var(--zon-soft), var(--zon))',
          'box-shadow': '0 0 0 1px rgba(47,224,172,0.4), 0 10px 30px -12px var(--zon-glow)',
        },
      ),
      css('&:hover').styles(raw: {
        'box-shadow': '0 0 0 1px rgba(123,242,206,0.6), 0 16px 40px -14px rgba(47,224,172,0.55)',
      }),
    ]),

    css('.btn-ghost', [
      css('&').styles(
        color: .variable('--fg'),
        backgroundColor: .rgba(255, 255, 255, 0.03),
        raw: {'border-color': 'var(--edge-2)', 'backdrop-filter': 'blur(8px)'},
      ),
      css('&:hover').styles(
        backgroundColor: .rgba(255, 255, 255, 0.06),
        raw: {'border-color': 'var(--zon-deep)'},
      ),
    ]),

    css('.btn-quiet', [
      css('&').styles(
        padding: .symmetric(vertical: 8.px, horizontal: 12.px),
        color: .variable('--fg-dim'),
        fontSize: 14.px,
        fontWeight: .w500,
      ),
      css('&:hover').styles(color: .variable('--fg'), backgroundColor: .rgba(255, 255, 255, 0.05)),
    ]),
  ];
}

/// The logo mark. Renders the carved rune with a soft aura behind it.
class RuneMark extends StatelessComponent {
  const RuneMark({this.size = 34, this.glow = true, super.key});

  final int size;
  final bool glow;

  @override
  Component build(BuildContext context) {
    return span(
      classes: glow ? 'rune rune-glow' : 'rune',
      styles: Styles(width: size.px, height: size.px),
      [
        svg(
          width: size.px,
          height: size.px,
          viewBox: '0 0 64 64',
          attributes: const {'fill': 'none', 'aria-hidden': 'true'},
          [
            path(d: _runeUpper, attributes: _runeStroke, []),
            path(d: _runeLower, attributes: _runeStroke, []),
            circle(cx: '32', cy: '32', r: '11', attributes: _runeStroke, []),
            circle(cx: '32', cy: '32', r: '4.8', attributes: const {'fill': 'currentColor'}, []),
          ],
        ),
      ],
    );
  }

  /// Kept in step with `assets/logo.svg`, the artwork every icon is built from.
  /// [_runeLower] is [_runeUpper] turned a half circle about (32,32).
  static const _runeUpper = 'M10 20 20 10h34l-14.222 14.222';
  static const _runeLower = 'M54 44 44 54H10l14.222-14.222';

  static const _runeStroke = {
    'stroke': 'currentColor',
    'stroke-width': '6',
    'stroke-linejoin': 'miter',
    'stroke-miterlimit': '6',
  };

  @css
  static List<StyleRule> get styles => [
    css('.rune', [
      css('&').styles(
        display: .inlineFlex,
        position: .relative(),
        alignItems: .center,
        justifyContent: .center,
        raw: {'flex': '0 0 auto'},
      ),
      css('svg').styles(
        width: 100.percent,
        height: 100.percent,
        color: .variable('--zon'),
        raw: {'display': 'block'},
      ),
    ]),
    css('.rune-glow', [
      css('&::before').styles(
        content: '""',
        position: .absolute(top: .zero, left: .zero, right: .zero, bottom: .zero),
        zIndex: ZIndex(-1),
        radius: .circular(50.percent),
        filter: .blur(14.px),
        animation: Animation(name: 'rune-pulse', duration: 4.seconds, curve: .easeInOut),
        raw: {
          'background': 'radial-gradient(circle, var(--zon-glow), transparent 68%)',
          'animation-iteration-count': 'infinite',
        },
      ),
    ]),
    css.keyframes('rune-pulse', {
      '0%, 100%': Styles(opacity: 0.55, transform: .scale(1)),
      '50%': Styles(opacity: 1, transform: .scale(1.18)),
    }),
  ];
}

/// Section wrapper: consistent vertical rhythm plus an optional heading block.
class Section extends StatelessComponent {
  const Section({
    required this.children,
    this.id,
    this.eyebrow,
    this.title,
    this.lede,
    this.centered = false,
    this.classes,
    super.key,
  });

  final List<Component> children;
  final String? id;
  final String? eyebrow;
  final Component? title;
  final String? lede;
  final bool centered;
  final String? classes;

  @override
  Component build(BuildContext context) {
    final hasHead = eyebrow != null || title != null || lede != null;

    return section(id: id, classes: ['sec', if (centered) 'sec-center', if (classes != null) classes!].join(' '), [
      div(classes: 'wrap', [
        if (hasHead)
          div(classes: 'sec-head', [
            if (eyebrow case final text?) div(classes: 'eyebrow', [.text(text)]),
            if (title case final node?) h2(classes: 'sec-title', [node]),
            if (lede case final text?) p(classes: 'lede', [.text(text)]),
          ]),
        ...children,
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.sec', [
      css('&').styles(padding: .symmetric(vertical: 84.px)),
      css('.sec-head').styles(
        display: .flex,
        maxWidth: 760.px,
        margin: .only(bottom: 52.px),
        flexDirection: .column,
        gap: .all(18.px),
      ),
      css('.sec-title').styles(fontSize: 40.px, fontWeight: .w600),
    ]),
    css('.sec-center', [
      css('.sec-head').styles(
        margin: .only(bottom: 52.px, left: .auto, right: .auto),
        alignItems: .center,
        textAlign: .center,
      ),
      css('.eyebrow').styles(justifyContent: .center),
      css('.lede').styles(textAlign: .center),
    ]),
    css.media(MediaQuery.screen(maxWidth: 860.px), [
      css('.sec').styles(padding: .symmetric(vertical: 60.px)),
      css('.sec .sec-title').styles(fontSize: 30.px),
    ]),
  ];
}

/// `grid-template-columns: repeat([count], 1fr)`.
GridTemplate gridCols(int count) => GridTemplate(
  columns: GridTracks([
    GridTrack.repeat(TrackRepeat(count), [GridTrack(.fr(1))]),
  ]),
);

/// Explicitly weighted columns, e.g. `gridFr([1.15, 1])` for a wider left pane.
GridTemplate gridFr(List<double> fractions) => GridTemplate(
  columns: GridTracks([for (final fraction in fractions) GridTrack(.fr(fraction))]),
);

/// Highlights a run of text in the accent color. Used inside headings.
Component accent(String text) => span(classes: 'accent', [.text(text)]);

/// A monospace inline token, e.g. `client.db.listen`.
Component mono(String text) => code(classes: 'inline-code', [.text(text)]);

@css
List<StyleRule> get textStyles => [
  css('.accent').styles(raw: {
    'background': 'linear-gradient(120deg, var(--zon-soft), var(--zon) 45%, var(--sky))',
    '-webkit-background-clip': 'text',
    'background-clip': 'text',
    'color': 'transparent',
  }),
  css('.inline-code').styles(
    padding: .symmetric(vertical: 2.px, horizontal: 6.px),
    border: .all(color: .variable('--edge'), width: 1.px),
    radius: .circular(5.px),
    color: .variable('--zon-soft'),
    fontSize: 0.9.em,
    backgroundColor: .rgba(47, 224, 172, 0.07),
  ),
];

/// Arrow used on the primary CTAs.
Component arrowIcon() => svg(
  width: 15.px,
  height: 15.px,
  viewBox: '0 0 16 16',
  attributes: const {'fill': 'none', 'aria-hidden': 'true'},
  [
    path(
      d: 'M3 8h9.5M8.5 4l4 4-4 4',
      attributes: const {
        'stroke': 'currentColor',
        'stroke-width': '1.7',
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
      },
      [],
    ),
  ],
);

/// GitHub glyph for the nav and footer.
Component githubIcon([double size = 17]) => svg(
  width: size.px,
  height: size.px,
  viewBox: '0 0 16 16',
  attributes: const {'fill': 'currentColor', 'aria-hidden': 'true'},
  [
    path(
      d: 'M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 '
          '0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 '
          '1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 '
          '0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.4 7.4 0 0 1 2-.27c.68 0 1.36.09 '
          '2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 '
          '3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z',
      [],
    ),
  ],
);

/// A pill linking out to the docs, used at the end of feature sections.
Component docsLink(String label, String href) => a(
  classes: 'docs-link',
  href: href,
  target: .blank,
  attributes: const {'rel': 'noopener'},
  [.text(label), arrowIcon()],
);

@css
List<StyleRule> get docsLinkStyles => [
  css('.docs-link', [
    css('&').styles(
      display: .inlineFlex,
      alignItems: .center,
      gap: .all(7.px),
      color: .variable('--zon'),
      fontFamily: .variable('--sans'),
      fontSize: 14.px,
      fontWeight: .w600,
    ),
    css('svg').styles(transition: Transition('transform', duration: 160.ms, curve: .easeOut)),
    css('&:hover svg').styles(transform: .translate(x: 3.px)),
  ]),
];

/// Shared reference so components can link out without importing [Links] twice.
typedef L = Links;
