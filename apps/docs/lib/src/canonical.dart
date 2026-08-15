/// The one place that turns a route into the URL the world sees.
///
/// GitHub Pages serves `foo/index.html` for `foo/` and 301-redirects `/foo` to
/// `/foo/`. A sitemap or a `rel="canonical"` that names the redirecting form
/// hands a crawler an extra hop and a second URL for the same page, so
/// everything public — `web/sitemap.xml`, `<link rel="canonical">` and
/// `og:url` — has to agree on the trailing slash. Sharing one function is what
/// makes that agreement structural rather than remembered.
library;

/// Absolute URL for [route] under [origin].
///
/// [route] is a root-absolute path as it appears in `navigation.dart` (`/`,
/// `/operations/streaming`); [origin] is the site's `url` from
/// `content/_data/site.yaml` (`https://docs.zonai.dev`), with or without a
/// trailing slash.
String canonicalUrl(String origin, String route) {
  final base = origin.replaceAll(RegExp(r'/+$'), '');
  if (route.isEmpty || route == '/') return '$base/';
  final path = route.startsWith('/') ? route : '/$route';
  return path.endsWith('/') ? '$base$path' : '$base$path/';
}
