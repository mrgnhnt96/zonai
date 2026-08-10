/// The entrypoint for the **server** environment.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/code_block.dart';
import 'package:jaspr_content/components/header.dart';
import 'package:jaspr_content/components/image.dart';
import 'package:jaspr_content/components/theme_toggle.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import 'components/cards.dart';
import 'components/docs_sidebar.dart';
import 'components/search.dart';
import 'main.server.options.dart';
import 'src/navigation.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    ContentApp(
      templateEngine: MustacheTemplateEngine(),
      parsers: [MarkdownParser()],
      extensions: [
        HeadingAnchorsExtension(),
        TableOfContentsExtension(),
      ],
      components: [
        Callout(),
        CodeBlock(grammars: {
          for (final lang in const [
            'sh', 'bash', 'json', 'yaml', 'sql', 'nginx', 'ini', 'html',
            'dockerfile', 'typescript', 'text', 'rust', 'ruby', 'python',
            'kotlin', 'javascript', 'java', 'go', 'css', 'toml',
          ])
            lang: '{"name":"$lang","scopeName":"source.$lang","patterns":[]}',
        }),
        Image(zoom: true),
        const CardGrid(),
        const Card(),
        const SectionCards(),
      ],
      layouts: [
        ZonaiDocsLayout(
          header: Header(
            title: 'Zonai',
            logo: '/images/logo.svg',
            items: [
              const DocsSearch(),
              const _GitHubLink(),
              ThemeToggle(),
            ],
          ),
          sidebar: const DocsSidebar(),
        ),
      ],
      theme: ContentTheme(
        primary: ThemeColor(ThemeColors.blue.$500, dark: ThemeColors.blue.$300),
        background: ThemeColor(ThemeColors.slate.$50, dark: ThemeColors.zinc.$950),
      ),
    ),
  );
}

/// [DocsLayout] with breadcrumbs, prev/next links, and site-level
/// description / OG image / keywords fallbacks.
///
/// [buildBody] reproduces `DocsLayout`'s DOM rather than calling `super`,
/// because the upstream layout offers no hook between the sidebar and the page
/// title. The class names are kept identical so the CSS that
/// `super.buildHead` emits still applies — if `jaspr_content` changes its
/// layout markup, this needs to follow.
final class ZonaiDocsLayout extends DocsLayout {
  const ZonaiDocsLayout({super.sidebar, super.header, super.footer});

  @override
  Iterable<Component> buildHead(Page page) sync* {
    yield* super.buildHead(page);
    yield Style(styles: _styles);

    final pageData = page.data.page;
    final siteData = page.data.site;

    if (pageData['description'] == null) {
      if (siteData['description'] case final String description) {
        yield meta(name: 'description', content: description);
        yield meta(attributes: {'property': 'og:description'}, content: description);
      }
    }

    if (pageData['keywords'] == null) {
      if (siteData['keywords'] case final List keywords) {
        yield meta(name: 'keywords', content: keywords.join(', '));
      } else if (siteData['keywords'] case final String keywords) {
        yield meta(name: 'keywords', content: keywords);
      }
    }

    if (pageData['image'] == null) {
      if (siteData['image'] case final String image) {
        final absolute = switch (siteData['url']) {
          final String url when image.startsWith('/') =>
            '${url.replaceAll(RegExp(r'/+$'), '')}$image',
          _ => image,
        };
        yield meta(attributes: {'property': 'og:image'}, content: absolute);
      }
    }
  }

  @override
  Component buildBody(Page page, Component child) {
    final pageData = page.data.page;
    final route = page.url;
    final group = groupFor(route);

    return div(classes: 'docs', [
      if (this.header case final headerComponent?)
        div(
          classes: 'header-container',
          attributes: {if (sidebar != null) 'data-has-sidebar': ''},
          [headerComponent],
        ),
      div(classes: 'main-container', [
        div(classes: 'sidebar-barrier', attributes: {'role': 'button'}, []),
        if (sidebar case final sidebar?) div(classes: 'sidebar-container', [sidebar]),
        main_([
          div([
            div(classes: 'content-container', [
              div(classes: 'content-header', [
                if (group != null)
                  nav(classes: 'breadcrumbs', attributes: {'aria-label': 'Breadcrumb'}, [
                    a(href: '/', [Component.text('Docs')]),
                    span(classes: 'breadcrumb-sep', [Component.text('/')]),
                    span([Component.text(group.title)]),
                  ]),
                if (pageData['title'] case final String title) h1([Component.text(title)]),
                if (pageData['description'] case final String description) p([Component.text(description)]),
                if (pageData['image'] case final String image) img(src: image, alt: pageData['imageAlt'] as String?),
              ]),
              child,
              div(classes: 'content-footer', [
                _PageNav(route: route),
                if (this.footer case final footerComponent?) footerComponent,
              ]),
            ]),
            aside(classes: 'toc', [
              if (page.data['toc'] case final TableOfContents toc)
                div([
                  h3([Component.text('On this page')]),
                  toc.build(),
                ]),
            ]),
          ]),
        ]),
      ]),
    ]);
  }
}

/// Previous/next links along the reading order defined in [navigation].
final class _PageNav extends StatelessComponent {
  const _PageNav({required this.route});

  final String route;

  @override
  Component build(BuildContext context) {
    final (:previous, :next) = neighborsOf(route);
    if (previous == null && next == null) return const Component.empty();

    return nav(classes: 'page-nav', attributes: {'aria-label': 'Pagination'}, [
      if (previous != null)
        a(classes: 'page-nav-link page-nav-prev', href: previous.href, [
          span(classes: 'page-nav-label', [Component.text('Previous')]),
          span(classes: 'page-nav-title', [Component.text(previous.title)]),
        ])
      else
        span([]),
      if (next != null)
        a(classes: 'page-nav-link page-nav-next', href: next.href, [
          span(classes: 'page-nav-label', [Component.text('Next')]),
          span(classes: 'page-nav-title', [Component.text(next.title)]),
        ]),
    ]);
  }
}

/// A compact repository link for the header.
final class _GitHubLink extends StatelessComponent {
  const _GitHubLink();

  @override
  Component build(BuildContext context) {
    final url = switch (context.page.data.site['social']) {
      final List social => social
          .whereType<Map>()
          .where((entry) => entry['name'] == 'GitHub')
          .map((entry) => entry['url'])
          .whereType<String>()
          .firstOrNull,
      _ => null,
    };
    if (url == null) return const Component.empty();

    return a(
      classes: 'header-icon-link',
      href: url,
      attributes: {'aria-label': 'Zonai on GitHub', 'target': '_blank', 'rel': 'noreferrer'},
      [RawText(_githubIcon)],
    );
  }
}

const _githubIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" '
    'aria-hidden="true"><path d="M12 .5C5.37.5 0 5.87 0 12.5c0 5.3 3.44 9.8 8.2 11.39.6.11.82-.26.82-.58 '
    'l-.01-2.05c-3.34.73-4.04-1.61-4.04-1.61-.55-1.39-1.34-1.76-1.34-1.76-1.09-.75.08-.73.08-.73 1.2.08 '
    '1.84 1.24 1.84 1.24 1.07 1.83 2.81 1.3 3.5.99.11-.78.42-1.3.76-1.6-2.67-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 '
    '1.24-3.22-.13-.3-.54-1.52.11-3.18 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 0 1 6.005 0c2.28-1.55 3.29-1.23 '
    '3.29-1.23.66 1.66.25 2.88.12 3.18.77.84 1.24 1.91 1.24 3.22 0 4.61-2.81 5.62-5.49 5.92.43.37.81 1.1.81 '
    '2.22l-.01 3.29c0 .32.21.7.82.58A12 12 0 0 0 24 12.5C24 5.87 18.63.5 12 .5z"/></svg>';

List<StyleRule> get _styles => [
  // `DocsLayout` sets the page description to font-size 1.25rem with an equal
  // line-height, so any description that wraps collides with itself.
  css('.docs .content-header p').styles(lineHeight: 1.6.em, opacity: .75),

  // Inline `<kbd>` in markdown; the content theme has no rule for it.
  css('.content kbd').styles(
    padding: Padding.symmetric(horizontal: .3125.rem, vertical: .0625.rem),
    radius: BorderRadius.circular(5.px),
    border: Border.all(width: 1.px, color: Color('color-mix(in srgb, currentColor 25%, transparent)')),
    fontSize: .8125.em,
    fontFamily: FontFamily.list([FontFamilies.monospace]),
    whiteSpace: WhiteSpace.noWrap,
  ),

  css('.header-icon-link', [
    css('&').styles(
      display: Display.flex,
      alignItems: AlignItems.center,
      padding: Padding.all(.6.rem),
      radius: BorderRadius.circular(8.px),
      color: Color('inherit'),
      opacity: .8,
    ),
    css('&:hover').styles(opacity: 1, backgroundColor: Color('color-mix(in srgb, currentColor 5%, transparent)')),
  ]),

  css('.breadcrumbs', [
    css('&').styles(
      display: Display.flex,
      gap: Gap.column(.5.rem),
      margin: Margin.only(bottom: .625.rem),
      fontSize: .8125.rem,
      opacity: .6,
    ),
    css('a').styles(color: Color('inherit'), textDecoration: TextDecoration.none),
    css('a:hover').styles(textDecoration: TextDecoration(line: TextDecorationLine.underline)),
    css('.breadcrumb-sep').styles(opacity: .5),
  ]),

  css('.page-nav', [
    css('&').styles(
      display: Display.flex,
      gap: Gap.column(1.rem),
      justifyContent: JustifyContent.spaceBetween,
      margin: Margin.only(top: 3.rem),
      padding: Padding.only(top: 1.5.rem),
      border: Border.only(top: BorderSide(width: 1.px, color: Color('color-mix(in srgb, currentColor 12%, transparent)'))),
    ),
    css('.page-nav-link', [
      css('&').styles(
        display: Display.flex,
        flexDirection: FlexDirection.column,
        gap: Gap.row(.125.rem),
        maxWidth: 48.percent,
        padding: Padding.symmetric(horizontal: 1.rem, vertical: .75.rem),
        radius: BorderRadius.circular(10.px),
        border: Border.all(width: 1.px, color: Color('color-mix(in srgb, currentColor 12%, transparent)')),
        textDecoration: TextDecoration.none,
        color: Color('inherit'),
        transition: Transition('all', duration: 150.ms, curve: Curve.easeInOut),
      ),
      css('&:hover').styles(
        border: Border.all(width: 1.px, color: Color('color-mix(in srgb, currentColor 28%, transparent)')),
        backgroundColor: Color('color-mix(in srgb, currentColor 4%, transparent)'),
      ),
      css('.page-nav-label').styles(fontSize: .6875.rem, opacity: .55, textTransform: TextTransform.upperCase, letterSpacing: .04.em),
      css('.page-nav-title').styles(fontWeight: FontWeight.w600, fontSize: .9375.rem, color: ContentColors.primary),
    ]),
    css('.page-nav-next').styles(textAlign: TextAlign.right, margin: Margin.only(left: Unit.auto)),
  ]),
];
