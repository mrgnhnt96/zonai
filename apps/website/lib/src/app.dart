/// The page shell: document head, then every section in reading order.
library;

import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'sections/dashboard.dart';
import 'sections/features.dart';
import 'sections/footer.dart';
import 'sections/hero.dart';
import 'sections/honest.dart';
import 'sections/live.dart';
import 'sections/nav.dart';
import 'sections/start.dart';
import 'theme.dart';

const _title = 'Zonai: self-hosted Dart backend framework. Your schema is the API';
const _description =
    'A self-hosted backend framework for Dart. Define tables in Dart and get a REST API with auth, rules, live query '
    'streams, file uploads, email and cron. Free, open source and MIT licensed.';
const _origin = 'https://zonai.dev';

const _headingFont = '/fonts/space-grotesk-latin-wght-normal.woff2';
const _bodyFont = '/fonts/inter-latin-wght-normal.woff2';

// Written by hand because `css.fontFace` cannot express a variable weight range
// or `font-display`.
const _fontFaces =
    "@font-face{font-family:'Space Grotesk';font-style:normal;font-weight:300 700;font-display:swap;"
    "src:url('$_headingFont') format('woff2')}"
    "@font-face{font-family:'Inter';font-style:normal;font-weight:100 900;font-display:swap;"
    "src:url('$_bodyFont') format('woff2')}";

final _structuredData = jsonEncode({
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'WebSite',
      '@id': '$_origin/#website',
      'url': '$_origin/',
      'name': 'Zonai',
      'publisher': {'@id': '$_origin/#organization'},
    },
    {
      '@type': 'Organization',
      '@id': '$_origin/#organization',
      'name': 'Zonai',
      'url': '$_origin/',
      'logo': '$_origin/images/logo-192.png',
      'sameAs': [Links.github],
    },
    {
      '@type': 'SoftwareApplication',
      'name': 'Zonai',
      'url': '$_origin/',
      'description': _description,
      'applicationCategory': 'DeveloperApplication',
      'operatingSystem': 'macOS, Linux, Windows',
      'softwareVersion': zonaiVersion,
      'license': '${Links.github}/blob/main/LICENSE',
      'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
      'publisher': {'@id': '$_origin/#organization'},
    },
  ],
});

Component _fontPreload(String href) => link(
  rel: 'preload',
  href: href,
  attributes: const {'as': 'font', 'type': 'font/woff2', 'crossorigin': ''},
);

class ZonaiSite extends StatelessComponent {
  const ZonaiSite({super.key});

  @override
  Component build(BuildContext context) {
    return Document(
      title: _title,
      lang: 'en',
      meta: {
        'description': _description,
        'theme-color': '#05080A',
        'keywords': 'Dart backend, Flutter backend, BaaS, SQLite, live queries, realtime, zonai, Dart REST API',
      },
      head: [
        link(rel: 'canonical', href: _origin),
        link(rel: 'icon', type: 'image/png', href: '/favicon.png'),
        link(rel: 'apple-touch-icon', href: '/images/logo-192.png'),

        // Open Graph / Twitter.
        meta(attributes: const {'property': 'og:type'}, content: 'website'),
        meta(attributes: const {'property': 'og:site_name'}, content: 'Zonai'),
        meta(attributes: const {'property': 'og:title'}, content: _title),
        meta(attributes: const {'property': 'og:description'}, content: _description),
        meta(attributes: const {'property': 'og:url'}, content: _origin),
        meta(attributes: const {'property': 'og:image'}, content: '$_origin/images/og.png'),
        meta(attributes: const {'property': 'og:image:width'}, content: '1200'),
        meta(attributes: const {'property': 'og:image:height'}, content: '630'),
        meta(name: 'twitter:card', content: 'summary_large_image'),
        meta(name: 'twitter:title', content: _title),
        meta(name: 'twitter:description', content: _description),
        meta(name: 'twitter:image', content: '$_origin/images/og.png'),

        _fontPreload(_headingFont),
        _fontPreload(_bodyFont),
        Component.element(tag: 'style', children: [RawText(_fontFaces)]),

        Component.element(
          tag: 'script',
          attributes: const {'type': 'application/ld+json'},
          children: [RawText(_structuredData)],
        ),
      ],
      body: div(classes: 'site', [
        a(classes: 'skip', href: '#main', [.text('Skip to content')]),
        const SiteNav(),
        main_(id: 'main', const [
          Hero(),
          LiveQueries(),
          AdminDashboard(),
          Features(),
          Honest(),
          QuickStart(),
          FinalCta(),
        ]),
        const SiteFooter(),
      ]),
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.skip', [
      css('&').styles(
        position: .absolute(top: (-100).px, left: 12.px),
        zIndex: ZIndex(100),
        padding: .symmetric(vertical: 10.px, horizontal: 16.px),
        radius: .circular(8.px),
        color: .variable('--void'),
        fontWeight: .w600,
        backgroundColor: .variable('--zon'),
      ),
      css('&:focus').styles(
        position: .absolute(top: 12.px, left: 12.px),
      ),
    ]),
  ];
}
