/// Platform support and direct download links for the CLI.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../interactive/install_command.dart';
import '../theme.dart';
import '../ui.dart';

/// Platform glyphs on a 24×24 grid.
const _glyphs = <String, String>{
  'apple':
      'M15.8 12.6c0-2.2 1.8-3.2 1.9-3.3-1-1.5-2.6-1.7-3.2-1.7-1.4-.1-2.7.8-3.4.8s-1.8-.8-2.9-.8c-1.5 0-2.9.9-3.6 2.2'
      '-1.6 2.7-.4 6.7 1.1 8.9.7 1.1 1.6 2.3 2.7 2.2 1.1 0 1.5-.7 2.8-.7s1.7.7 2.9.7c1.2 0 1.9-1.1 2.6-2.1.8-1.2 1.2-2.4 '
      '1.2-2.4s-2.1-.8-2.1-3.8ZM13.6 6.1c.6-.7 1-1.7.9-2.7-.9 0-2 .6-2.6 1.3-.6.6-1.1 1.7-.9 2.6 1 .1 2-.5 2.6-1.2Z',
  'linux':
      'M12 2.8c-2 0-3.1 1.7-3.1 3.7 0 1.3.2 2 .1 2.8-.2 1.1-1.4 2.6-2 4.1-.5 1.4-.4 2.7-.2 3.4.2.7 0 1.3-.4 1.9'
      '-.3.5-.1 1 .5 1.1 1 .2 2.3.5 3.2.9.8.4 1.9.4 2.7 0 .9-.4 2.2-.7 3.2-.9.6-.1.8-.6.5-1.1-.4-.6-.6-1.2-.4-1.9'
      '.2-.7.3-2-.2-3.4-.6-1.5-1.8-3-2-4.1-.1-.8.1-1.5.1-2.8 0-2-1.1-3.7-3.1-3.7Zm-1.3 3.4h.01M13.3 6.2h.01'
      'M10.6 9.4c.5.4 1 .6 1.4.6s.9-.2 1.4-.6',
  'windows':
      'M3.6 6.1 10.4 5.2v6.3H3.6V6.1Zm0 11.8 6.8.9v-6.2H3.6v5.3Zm8.1 1L20.4 20V12.2h-8.7v6.7Zm0-14 8.7-1.2v7.7h-8.7V4.9Z',
  'spark': 'M12 3.2 13.9 9l5.9 1.9-5.9 1.9L12 18.8l-1.9-5.9L4.2 11 10.1 9 12 3.2Z',
};

Component _platformIcon(String name) => svg(
  width: 19.px,
  height: 19.px,
  viewBox: '0 0 24 24',
  attributes: const {'fill': 'none', 'aria-hidden': 'true'},
  [
    path(
      d: _glyphs[name]!,
      attributes: const {
        'stroke': 'currentColor',
        'stroke-width': '1.4',
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
      },
      [],
    ),
  ],
);

Component _downloadIcon() => svg(
  width: 15.px,
  height: 15.px,
  viewBox: '0 0 16 16',
  attributes: const {'fill': 'none', 'aria-hidden': 'true'},
  [
    path(
      d: 'M8 2.5v7.5m0 0L5 7.2m3 2.8 3-2.8M2.8 12.2v.6a1 1 0 0 0 1 1h8.4a1 1 0 0 0 1-1v-.6',
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

class Downloads extends StatelessComponent {
  const Downloads({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'download',
      eyebrow: 'Download',
      title: .fragment([.text('Every platform, '), accent('one binary'), .text('.')]),
      lede:
          'The CLI runs from your project root. Grab the universal build and it works out which OS and architecture '
          'you are on by itself; or take the exact one you need.',
      children: [
        div(classes: 'dl-top', [
          // The recommended path: curl, or the same file as a click.
          div(classes: 'pane dl-card dl-hero', [
            div(classes: 'dl-hero-head', [
              span(classes: 'dl-hero-icon', [_platformIcon(universalDownload.icon)]),
              div([
                h3([.text(universalDownload.os)]),
                p([.text(universalDownload.note)]),
              ]),
              span(classes: 'dl-size', [.text(universalDownload.size)]),
            ]),
            const InstallCommand(command: installCommand),
            div(classes: 'dl-hero-actions', [
              a(classes: 'dl-btn', href: universalDownload.href, [
                _downloadIcon(),
                .text('Download the universal binary'),
              ]),
            ]),
            p(classes: 'dl-note', [
              .text('One self-extracting file containing macOS arm64, macOS x64, Linux x64 and Linux arm64. '),
              .text('It caches the right build on first run. '),
              strong([.text('Not a Windows executable')]),
              .text(' — Windows takes the zip below.'),
            ]),
          ]),

          // Windows gets equal billing rather than a footnote.
          div(classes: 'pane dl-card dl-windows', [
            div(classes: 'dl-hero-head', [
              span(classes: 'dl-hero-icon', [_platformIcon(windowsDownload.icon)]),
              div([
                h3([.text(windowsDownload.os)]),
                p([.text(windowsDownload.note)]),
              ]),
              span(classes: 'dl-size', [.text(windowsDownload.size)]),
            ]),
            div(classes: 'dl-hero-actions', [
              a(classes: 'dl-btn', href: windowsDownload.href, [
                _downloadIcon(),
                .text('Download for Windows'),
              ]),
            ]),
            p(classes: 'dl-note', [
              .text('Extract the zip and put '),
              mono('zonai.exe'),
              .text(' in your project root.'),
            ]),
          ]),
        ]),

        h3(classes: 'dl-sub', [.text('All builds')]),
        ul(classes: 'dl-grid', [
          for (final d in downloads)
            li([
              a(classes: 'dl-row', href: d.href, [
                span(classes: 'dl-row-icon', [_platformIcon(d.icon)]),
                span(classes: 'dl-row-os', [.text(d.os)]),
                span(classes: 'dl-row-note', [.text(d.note)]),
                span(classes: 'dl-row-size', [.text(d.size)]),
                _downloadIcon(),
              ]),
            ]),
        ]),

        div(classes: 'dl-foot', [
          span(classes: 'dl-foot-ver', [
            .text('Latest CLI release: '),
            a(
              href: Links.release,
              target: .blank,
              attributes: const {'rel': 'noopener'},
              [
                strong([.text('v$zonaiVersion')]),
              ],
            ),
          ]),
          div(classes: 'dl-foot-links', [
            docsLink('Release notes', Links.release),
            docsLink('All releases', Links.allReleases),
            docsLink('Install guide', Links.installation),
          ]),
        ]),

        p(classes: 'dl-update', [
          .text('Already installed? '),
          mono('./zonai version check'),
          .text(' tells you if there is a newer build, and '),
          mono('./zonai version update'),
          .text(' replaces the binary in place.'),
        ]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.dl-top').styles(
      display: .grid,
      gridTemplate: gridFr([1.25, 1]),
      gap: .all(18.px),
      alignItems: .start,
    ),

    // Nest under ONE class, never a comma-separated pair: Jaspr resolves
    // `css('.a, .b', [css('.child')])` to `.a, .b .child` — which silently
    // applies the child's rules to `.a` itself.
    css('.dl-card', [
      css('&').styles(
        display: .flex,
        padding: .all(22.px),
        flexDirection: .column,
        gap: .all(16.px),
        backgroundColor: .rgba(255, 255, 255, 0.018),
        raw: {'min-width': '0'},
      ),
      css('.dl-hero-head').styles(display: .flex, alignItems: .center, gap: .all(13.px)),
      css('.dl-hero-icon').styles(
        display: .flex,
        width: 40.px,
        height: 40.px,
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(10.px),
        alignItems: .center,
        justifyContent: .center,
        color: .variable('--zon'),
        backgroundColor: .rgba(47, 224, 172, 0.07),
        raw: {'flex': '0 0 auto'},
      ),
      css('h3').styles(color: .variable('--fg'), fontSize: 17.px, fontWeight: .w600),
      css('.dl-hero-head p').styles(color: .variable('--fg-mute'), fontSize: 13.px),
      css('.dl-size').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 11.5.px,
        whiteSpace: .noWrap,
        raw: {'margin-left': 'auto', 'flex': '0 0 auto'},
      ),
      css('.dl-hero-actions').styles(display: .flex, flexWrap: .wrap, gap: .all(10.px)),
      css('.dl-note').styles(color: .variable('--fg-mute'), fontSize: 12.5.px, lineHeight: 1.6.em),
      css('.dl-note strong').styles(color: .variable('--fg-dim'), fontWeight: .w600),
    ]),
    // The universal build is the recommendation; give it a warmer edge.
    css('.dl-hero').styles(raw: {'border-color': 'var(--zon-deep)'}),
    css('.dl-windows .dl-hero-icon').styles(
      color: .variable('--sky'),
      backgroundColor: .rgba(91, 200, 250, 0.08),
    ),

    css('.dl-btn', [
      css('&').styles(
        display: .inlineFlex,
        padding: .symmetric(vertical: 10.px, horizontal: 16.px),
        border: .all(color: .variable('--edge-2'), width: 1.px),
        radius: .circular(9.px),
        transition: Transition.combine([
          Transition('background-color', duration: 160.ms),
          Transition('border-color', duration: 160.ms),
          Transition('transform', duration: 160.ms, curve: .easeOut),
        ]),
        alignItems: .center,
        gap: .all(9.px),
        color: .variable('--fg'),
        fontFamily: .variable('--sans'),
        fontSize: 13.5.px,
        fontWeight: .w600,
        backgroundColor: .rgba(255, 255, 255, 0.04),
      ),
      css('&:hover').styles(
        transform: .translate(y: (-2).px),
        color: .variable('--fg'),
        backgroundColor: .rgba(47, 224, 172, 0.1),
        raw: {'border-color': 'var(--zon-deep)'},
      ),
    ]),

    css('.dl-sub').styles(
      margin: .only(top: 40.px, bottom: 14.px),
      color: .variable('--fg-mute'),
      fontFamily: .variable('--mono'),
      fontSize: 12.px,
      fontWeight: .w500,
      textTransform: .upperCase,
      letterSpacing: 1.4.px,
    ),

    css('.dl-grid', [
      css('&').styles(
        display: .grid,
        margin: .zero,
        padding: .zero,
        gridTemplate: gridCols(2),
        gap: .all(8.px),
        listStyle: .none,
      ),
      css('.dl-row').styles(
        display: .flex,
        padding: .symmetric(vertical: 12.px, horizontal: 15.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(10.px),
        transition: Transition.combine([
          Transition('background-color', duration: 160.ms),
          Transition('border-color', duration: 160.ms),
        ]),
        alignItems: .center,
        gap: .all(11.px),
        color: .variable('--fg-dim'),
        fontSize: 13.5.px,
        backgroundColor: .rgba(255, 255, 255, 0.015),
      ),
      css('.dl-row:hover').styles(
        color: .variable('--fg'),
        backgroundColor: .rgba(255, 255, 255, 0.04),
        raw: {'border-color': 'var(--zon-deep)'},
      ),
      css('.dl-row-icon').styles(
        display: .flex,
        alignItems: .center,
        color: .variable('--fg-mute'),
        raw: {'flex': '0 0 auto'},
      ),
      css('.dl-row:hover .dl-row-icon').styles(color: .variable('--zon')),
      css('.dl-row-os').styles(color: .variable('--fg'), fontWeight: .w600, raw: {'flex': '0 0 auto'}),
      css('.dl-row-note').styles(color: .variable('--fg-mute'), fontFamily: .variable('--mono'), fontSize: 11.5.px),
      css('.dl-row-size').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 11.px,
        whiteSpace: .noWrap,
        raw: {'margin-left': 'auto'},
      ),
    ]),

    css('.dl-foot', [
      css('&').styles(
        display: .flex,
        margin: .only(top: 26.px),
        padding: .only(top: 20.px),
        flexWrap: .wrap,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: .all(16.px),
        raw: {'border-top': '1px solid var(--edge)'},
      ),
      css('.dl-foot-ver').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 13.px,
      ),
      css('.dl-foot-ver strong').styles(color: .variable('--zon'), fontWeight: .w600),
      css('.dl-foot-links').styles(display: .flex, flexWrap: .wrap, gap: .all(22.px)),
    ]),

    css('.dl-update').styles(
      margin: .only(top: 18.px),
      color: .variable('--fg-mute'),
      fontSize: 13.px,
      lineHeight: 1.8.em,
    ),

    css.media(MediaQuery.screen(maxWidth: 900.px), [
      css('.dl-top').styles(gridTemplate: gridCols(1)),
      css('.dl-grid').styles(gridTemplate: gridCols(1)),
    ]),
    css.media(MediaQuery.screen(maxWidth: 560.px), [
      css('.dl-row-note').styles(display: .none),
      css('.dl-btn').styles(width: 100.percent, justifyContent: .center),
    ]),
  ];
}
