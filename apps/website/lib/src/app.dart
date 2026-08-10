/// The page shell: document head, then every section in reading order.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'sections/dashboard.dart';
import 'sections/download.dart';
import 'sections/features.dart';
import 'sections/footer.dart';
import 'sections/hero.dart';
import 'sections/honest.dart';
import 'sections/live.dart';
import 'sections/nav.dart';
import 'sections/pipeline.dart';
import 'sections/start.dart';
import 'sections/tour.dart';

const _title = 'Zonai — Your schema is the API';
const _description =
    'A batteries-included Dart backend framework. Define tables in Dart and get a complete REST API with auth, '
    'authorization rules, live query streams, file uploads, email, and cron — compiled into one binary you own.';
const _origin = 'https://zonai.dev';

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

        // Fonts. Preconnect first so the display face lands with the hero.
        link(rel: 'preconnect', href: 'https://fonts.googleapis.com'),
        link(rel: 'preconnect', href: 'https://fonts.gstatic.com', attributes: const {'crossorigin': ''}),
        link(
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2'
              '?family=Space+Grotesk:wght@500;600;700'
              '&family=Inter:wght@400;500;600'
              '&family=JetBrains+Mono:wght@400;500;600'
              '&display=swap',
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
          Pipeline(),
          Tour(),
          Honest(),
          Downloads(),
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
      css('&:focus').styles(position: .absolute(top: 12.px, left: 12.px)),
    ]),
  ];
}
