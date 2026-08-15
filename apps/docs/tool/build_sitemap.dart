/// Builds `web/sitemap.xml`, the crawl list for the docs site.
///
/// The site is statically generated and served from GitHub Pages, so nothing
/// at request time can enumerate its pages, and nothing links to a page that
/// is not in the sidebar. Without this file a crawler has to discover 80-odd
/// pages by following links from the index; with it, the whole set is one
/// fetch.
///
/// This walks `content/` exactly the way `build_search_index.dart` does, so
/// the two can never disagree about which routes exist.
///
/// Run it before `jaspr build` / `jaspr serve`:
///
/// ```sh
/// dart run tool/build_sitemap.dart
/// ```
///
/// Pass `--check` to verify the committed file is current without writing —
/// this is what CI uses to catch a content change that forgot to regenerate.
library;

import 'dart:io';

import 'package:zonai_docs/src/canonical.dart';
import 'package:zonai_docs/src/navigation.dart';

void main(List<String> args) {
  final check = args.contains('--check');

  final root = _docsRoot();
  final contentDir = Directory('${root.path}/content');
  if (!contentDir.existsSync()) {
    stderr.writeln('No content directory at ${contentDir.path}');
    exit(1);
  }

  final origin = _siteUrl(root);
  final xml = buildSitemap(origin, routesUnder(contentDir));
  final output = File('${root.path}/web/sitemap.xml');

  if (check) {
    final current = output.existsSync() ? output.readAsStringSync() : '';
    if (current != xml) {
      stderr.writeln('web/sitemap.xml is stale. Run: dart run tool/build_sitemap.dart');
      exit(1);
    }
    stdout.writeln('Sitemap is up to date.');
    return;
  }

  output.writeAsStringSync(xml);
  stdout.writeln('Wrote ${output.path} — ${routesUnder(contentDir).length} URLs.');
}

/// Every route rendered from `content/`, in sidebar reading order.
///
/// Reading order is not something a crawler acts on, but it keeps the diff of
/// this file readable: a new page shows up next to its neighbours instead of
/// wherever the filesystem happened to put it. Pages outside the sidebar (see
/// `unlistedRoutes`) sort alphabetically after the rest.
List<String> routesUnder(Directory contentDir) {
  final routes = [
    for (final file in contentDir.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.md')) routeFor(file.path, contentDir.path),
  ];

  final order = {for (final (i, item) in flatNavigation.indexed) item.href: i};
  routes.sort((a, b) {
    final aOrder = order[a], bOrder = order[b];
    if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
    if (aOrder != null) return -1;
    if (bOrder != null) return 1;
    return a.compareTo(b);
  });

  return routes;
}

/// `content/operations/streaming.md` -> `/operations/streaming`, `index.md` -> `/`.
String routeFor(String path, String contentPath) {
  var relative = path.substring(contentPath.length).replaceAll(r'\', '/');
  relative = relative.replaceFirst(RegExp(r'^/'), '').replaceFirst(RegExp(r'\.md$'), '');
  if (relative == 'index') return '/';
  return '/$relative';
}

/// Renders the sitemap XML for [routes] under [origin].
///
/// No `<lastmod>`: the only honest source for it is the file's last commit
/// date, and committing a generated file changes that date — the value would
/// be one commit stale the moment it was written. Google treats an unreliable
/// `lastmod` as noise, so an absent one is better than a wrong one.
///
/// No `<priority>` or `<changefreq>` either; Google ignores both.
String buildSitemap(String origin, List<String> routes) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');

  for (final route in routes) {
    buffer
      ..writeln('  <url>')
      ..writeln('    <loc>${canonicalUrl(origin, route)}</loc>')
      ..writeln('  </url>');
  }

  buffer.writeln('</urlset>');
  return buffer.toString();
}

/// Resolves the `apps/docs` directory whether invoked from there or from the
/// workspace root.
Directory _docsRoot() {
  final cwd = Directory.current;
  if (File('${cwd.path}/content/index.md').existsSync()) return cwd;
  final nested = Directory('${cwd.path}/apps/docs');
  if (File('${nested.path}/content/index.md').existsSync()) return nested;
  stderr.writeln('Run this from apps/docs (or the workspace root).');
  exit(1);
}

/// The site origin from `content/_data/site.yaml`.
///
/// Read rather than hardcoded so the domain lives in exactly one place — the
/// same key `main.server.dart` reads to build `og:image` and the canonical
/// link. Only the one scalar key is needed, so this matches it directly
/// instead of taking on a YAML dependency.
String _siteUrl(Directory root) {
  final file = File('${root.path}/content/_data/site.yaml');
  final match = RegExp(r'''^url:\s*['"]?([^'"\s]+)''', multiLine: true).firstMatch(file.readAsStringSync());
  if (match == null) {
    stderr.writeln('No `url:` key in ${file.path}; the sitemap needs an absolute origin.');
    exit(1);
  }
  return match.group(1)!;
}
