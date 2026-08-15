/// Exercises the committed `web/sitemap.xml`.
///
/// The sitemap is the only thing telling a crawler that 80 pages exist, and
/// nothing on the site breaks when it goes stale — so a page added without
/// regenerating it would simply stay unindexed, silently. These tests are what
/// makes that loud.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_docs/src/canonical.dart';
import 'package:zonai_docs/src/navigation.dart';

import '../tool/build_sitemap.dart' show buildSitemap, routeFor, routesUnder;

/// Hardcoded rather than read from `site.yaml`: the published domain is the
/// thing under test. If `site.yaml` ever changes it, that should fail here and
/// be looked at, not be quietly adopted.
const _origin = 'https://docs.zonai.dev';

void main() {
  final sitemapFile = File('web/sitemap.xml');
  final contentDir = Directory('content');

  late String sitemap;
  late Set<String> locations;

  setUpAll(() {
    expect(
      sitemapFile.existsSync(),
      isTrue,
      reason: 'Run: dart run tool/build_sitemap.dart',
    );
    sitemap = sitemapFile.readAsStringSync();
    locations = {
      for (final match in RegExp(r'<loc>([^<]+)</loc>').allMatches(sitemap)) match.group(1)!,
    };
  });

  test('is current with content/', () {
    expect(
      sitemap,
      buildSitemap(_origin, routesUnder(contentDir)),
      reason: 'Run: dart run tool/build_sitemap.dart',
    );
  });

  test('lists every page under content/', () {
    final expected = {
      for (final file in contentDir.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.md')) canonicalUrl(_origin, routeFor(file.path, contentDir.path)),
    };
    expect(locations, expected);
  });

  test('covers every sidebar link', () {
    final linked = {for (final item in flatNavigation) canonicalUrl(_origin, item.href)};
    expect(linked.difference(locations), isEmpty);
  });

  // GitHub Pages 301s `/foo` to `/foo/`. A sitemap naming the redirecting form
  // costs a crawl hop on every page and reports as a soft duplicate.
  test('every URL is the form Pages serves without redirecting', () {
    expect(locations, everyElement(startsWith('$_origin/')));
    expect(locations, everyElement(endsWith('/')));
  });

  test('robots.txt points at the sitemap', () {
    final robots = File('web/robots.txt');
    expect(robots.existsSync(), isTrue);
    expect(robots.readAsStringSync(), contains('Sitemap: $_origin/sitemap.xml'));
  });
}
