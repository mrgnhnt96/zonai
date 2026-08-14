/// Sticky top navigation. Interactive for two reasons: the bar gains a border
/// and blur once the page scrolls, and small screens get a drop-down menu.
library;

import 'dart:async';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:universal_web/web.dart' as web;

import '../theme.dart';
import '../ui.dart';

const _navLinks = <(String, String)>[
  ('Features', '#features'),
  ('Live Queries', '#live'),
  ('Dashboard', '#dashboard'),
  ('Pipeline', '#pipeline'),
  ('Download', '#download'),
  ('Quick Start', '#start'),
];

@client
class SiteNav extends StatefulComponent {
  const SiteNav({super.key});

  @override
  State<SiteNav> createState() => SiteNavState();
}

class SiteNavState extends State<SiteNav> {
  bool _scrolled = false;
  bool _open = false;
  StreamSubscription<web.Event>? _scroll;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;

    _scroll = web.EventStreamProviders.scrollEvent.forTarget(web.window).listen((_) {
      final scrolled = web.window.scrollY > 12;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _scroll?.cancel();
    super.dispose();
  }

  /// jaspr's `onClick` calls `preventDefault()` on anchor elements, so the
  /// href navigation has to be replayed by hand here.
  void _navigate(String href) {
    if (_open) setState(() => _open = false);
    web.document.querySelector(href)?.scrollIntoView();
    web.window.location.hash = href;
  }

  @override
  Component build(BuildContext context) {
    return header(classes: ['nav', if (_scrolled) 'nav-stuck', if (_open) 'nav-open'].join(' '), [
      div(classes: 'wrap nav-inner', [
        a(classes: 'brand', href: '/', [
          const RuneMark(size: 30),
          span(classes: 'brand-name', [.text('zonai')]),
          span(classes: 'brand-ver', [.text('v$zonaiVersion')]),
        ]),

        nav(
          classes: 'nav-links',
          attributes: const {'aria-label': 'Sections'},
          [
            for (final (label, href) in _navLinks) a(href: href, onClick: () => _navigate(href), [.text(label)]),
          ],
        ),

        div(classes: 'nav-actions', [
          a(
            classes: 'nav-icon',
            href: Links.github,
            target: .blank,
            attributes: const {'rel': 'noopener', 'aria-label': 'Zonai on GitHub'},
            [githubIcon()],
          ),
          a(classes: 'nav-docs', href: Links.docs, [.text('Docs')]),
          LinkButton(label: 'Get Started', href: Links.quickStart, icon: arrowIcon()),
          button(
            classes: 'nav-burger',
            onClick: () => setState(() => _open = !_open),
            attributes: {'aria-expanded': '$_open', 'aria-label': 'Toggle menu'},
            [span([]), span([]), span([])],
          ),
        ]),
      ]),

      div(classes: 'nav-sheet', [
        for (final (label, href) in _navLinks) a(href: href, onClick: () => _navigate(href), [.text(label)]),
        a(href: Links.docs, [.text('Documentation')]),
        a(href: Links.github, target: .blank, attributes: const {'rel': 'noopener'}, [.text('GitHub')]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.nav', [
      css('&').styles(
        position: .sticky(top: .zero),
        zIndex: ZIndex(50),
        transition: Transition.combine([
          Transition('background-color', duration: 220.ms),
          Transition('border-color', duration: 220.ms),
        ]),
        raw: {
          'border-bottom': '1px solid transparent',
          'backdrop-filter': 'blur(14px)',
          '-webkit-backdrop-filter': 'blur(14px)',
        },
      ),
      css('&.nav-stuck').styles(
        backgroundColor: .rgba(5, 8, 10, 0.82),
        raw: {'border-bottom-color': 'var(--edge)'},
      ),

      css('.nav-inner').styles(
        display: .flex,
        height: 66.px,
        alignItems: .center,
        gap: .all(20.px),
      ),

      // Brand -----------------------------------------------------------------
      css('.brand').styles(
        display: .flex,
        alignItems: .center,
        gap: .all(10.px),
        color: .variable('--fg'),
        raw: {'flex': '0 0 auto'},
      ),
      css('.brand-name').styles(
        fontFamily: .variable('--sans'),
        fontSize: 19.px,
        fontWeight: .w700,
        letterSpacing: (-0.3).px,
      ),
      css('.brand-ver').styles(
        padding: .symmetric(vertical: 1.px, horizontal: 6.px),
        radius: .circular(999.px),
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 10.px,
        backgroundColor: .rgba(255, 255, 255, 0.04),
        raw: {'border': '1px solid var(--edge)'},
      ),

      // Center links ----------------------------------------------------------
      css('.nav-links').styles(
        display: .flex,
        alignItems: .center,
        gap: .all(4.px),
        raw: {'margin': '0 auto'},
      ),
      css('.nav-links a').styles(
        padding: .symmetric(vertical: 7.px, horizontal: 12.px),
        radius: .circular(8.px),
        transition: Transition.combine([
          Transition('color', duration: 160.ms),
          Transition('background-color', duration: 160.ms),
        ]),
        color: .variable('--fg-dim'),
        fontSize: 14.px,
        fontWeight: .w500,
      ),
      css('.nav-links a:hover').styles(
        color: .variable('--fg'),
        backgroundColor: .rgba(255, 255, 255, 0.05),
      ),

      // Right-hand actions ----------------------------------------------------
      css('.nav-actions').styles(
        display: .flex,
        alignItems: .center,
        gap: .all(8.px),
        raw: {'flex': '0 0 auto'},
      ),
      css('.nav-icon').styles(
        display: .inlineFlex,
        width: 34.px,
        height: 34.px,
        radius: .circular(8.px),
        transition: Transition('color', duration: 160.ms),
        alignItems: .center,
        justifyContent: .center,
        color: .variable('--fg-mute'),
      ),
      css('.nav-icon:hover').styles(color: .variable('--fg'), backgroundColor: .rgba(255, 255, 255, 0.05)),
      css('.nav-docs').styles(
        padding: .symmetric(vertical: 7.px, horizontal: 12.px),
        radius: .circular(8.px),
        color: .variable('--fg-dim'),
        fontSize: 14.px,
        fontWeight: .w500,
      ),
      css('.nav-docs:hover').styles(color: .variable('--fg'), backgroundColor: .rgba(255, 255, 255, 0.05)),
      css('.nav .btn').styles(
        padding: .symmetric(vertical: 8.px, horizontal: 15.px),
        fontSize: 13.5.px,
      ),

      // Burger ----------------------------------------------------------------
      css('.nav-burger').styles(
        display: .none,
        width: 36.px,
        height: 34.px,
        padding: .zero,
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(8.px),
        cursor: .pointer,
        flexDirection: .column,
        justifyContent: .center,
        alignItems: .center,
        gap: .all(4.px),
        backgroundColor: .rgba(255, 255, 255, 0.03),
      ),
      css('.nav-burger > span').styles(
        display: .block,
        width: 15.px,
        height: 1.5.px,
        radius: .circular(2.px),
        transition: Transition('transform', duration: 200.ms, curve: .easeOut),
        backgroundColor: .variable('--fg'),
      ),
      css('&.nav-open .nav-burger > span:first-child').styles(
        transform: .combine([.translate(y: 5.5.px), .rotate(45.deg)]),
      ),
      css('&.nav-open .nav-burger > span:nth-child(2)').styles(opacity: 0),
      css('&.nav-open .nav-burger > span:last-child').styles(
        transform: .combine([.translate(y: (-5.5).px), .rotate((-45).deg)]),
      ),

      // Mobile sheet ----------------------------------------------------------
      css('.nav-sheet').styles(
        display: .none,
        padding: .symmetric(vertical: 10.px, horizontal: .variable('--gutter')),
        flexDirection: .column,
        backgroundColor: .rgba(5, 8, 10, 0.96),
        raw: {'border-top': '1px solid var(--edge)'},
      ),
      css('.nav-sheet a').styles(
        padding: .symmetric(vertical: 12.px),
        color: .variable('--fg-dim'),
        fontFamily: .variable('--sans'),
        fontSize: 15.px,
        fontWeight: .w500,
        raw: {'border-bottom': '1px solid rgba(255,255,255,0.04)'},
      ),
      css('.nav-sheet a:last-child').styles(raw: {'border-bottom': 'none'}),
    ]),

    css.media(MediaQuery.screen(maxWidth: 980.px), [
      css('.nav .nav-links').styles(display: .none),
      css('.nav .nav-burger').styles(display: .flex),
      css('.nav .nav-docs').styles(display: .none),
      css('.nav.nav-open .nav-sheet').styles(display: .flex),
      css('.nav.nav-open').styles(
        backgroundColor: .rgba(5, 8, 10, 0.96),
        raw: {'border-bottom-color': 'var(--edge)'},
      ),
    ]),
    css.media(MediaQuery.screen(maxWidth: 520.px), [
      css('.nav .brand-ver').styles(display: .none),
      css('.nav .btn-label').styles(raw: {'display': 'none'}),
      css('.nav .btn').styles(
        padding: .symmetric(vertical: 8.px, horizontal: 11.px),
      ),
    ]),
  ];
}
