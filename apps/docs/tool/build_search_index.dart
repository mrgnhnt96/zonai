/// Builds `web/search-index.json`, the payload behind the docs site's ⌘K search.
///
/// The site is statically generated and served from GitHub Pages, so there is
/// no backend to query. Instead this walks `content/`, splits each page on its
/// headings, and emits one searchable record per section. The client component
/// in `lib/components/search.dart` fetches the result and scores it in the
/// browser.
///
/// Run it before `jaspr build` / `jaspr serve`:
///
/// ```sh
/// dart run tool/build_search_index.dart
/// ```
///
/// Pass `--check` to verify the committed index is current without writing —
/// this is what CI uses to catch a content change that forgot to regenerate.
library;

import 'dart:convert';
import 'dart:io';

import 'package:zonai_docs/src/navigation.dart';

/// Longest body excerpt kept per section.
///
/// Long enough to hold the paragraph a match lands in, short enough that the
/// whole index stays a single fast download.
const _maxSectionLength = 1200;

void main(List<String> args) {
  final check = args.contains('--check');

  final root = _docsRoot();
  final contentDir = Directory('${root.path}/content');
  if (!contentDir.existsSync()) {
    stderr.writeln('No content directory at ${contentDir.path}');
    exit(1);
  }

  final files = contentDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final documents = <Map<String, Object?>>[];
  final routes = <String>{};

  for (final file in files) {
    final route = _routeFor(file.path, contentDir.path);
    routes.add(route);
    documents.add(_indexPage(file, route));
  }

  final problems = _navigationProblems(routes);
  if (problems.isNotEmpty) {
    stderr.writeln('Navigation is out of sync with content/:');
    for (final problem in problems) {
      stderr.writeln('  - $problem');
    }
    stderr.writeln('\nFix lib/src/navigation.dart (or add the route to unlistedRoutes).');
    exit(1);
  }

  // Sort by reading order so that, all else equal, earlier pages win ties.
  final order = {for (final (i, item) in flatNavigation.indexed) item.href: i};
  documents.sort((a, b) {
    final aOrder = order[a['u']] ?? order.length;
    final bOrder = order[b['u']] ?? order.length;
    return aOrder.compareTo(bOrder);
  });

  final json = '${const JsonEncoder.withIndent('  ').convert({'v': 1, 'docs': documents})}\n';
  final output = File('${root.path}/web/search-index.json');

  if (check) {
    final current = output.existsSync() ? output.readAsStringSync() : '';
    if (current != json) {
      stderr.writeln(
        'web/search-index.json is stale. Run: dart run tool/build_search_index.dart',
      );
      exit(1);
    }
    stdout.writeln('Search index is up to date (${documents.length} pages).');
    return;
  }

  output.writeAsStringSync(json);

  final sections = documents.fold<int>(0, (sum, doc) => sum + (doc['s']! as List).length);
  stdout.writeln(
    'Wrote ${output.path} — ${documents.length} pages, $sections sections, '
    '${(json.length / 1024).toStringAsFixed(1)} KB.',
  );
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

/// `content/operations/streaming.md` -> `/operations/streaming`, `index.md` -> `/`.
String _routeFor(String path, String contentPath) {
  var relative = path.substring(contentPath.length).replaceAll(r'\', '/');
  relative = relative.replaceFirst(RegExp(r'^/'), '').replaceFirst(RegExp(r'\.md$'), '');
  if (relative == 'index') return '/';
  return '/$relative';
}

/// Content pages missing from the sidebar, and sidebar links with no page.
List<String> _navigationProblems(Set<String> routes) {
  final problems = <String>[];
  final linked = {for (final item in flatNavigation) item.href};

  for (final route in routes.difference(linked).difference(unlistedRoutes)) {
    problems.add('content$route.md is not linked from any sidebar group');
  }
  for (final href in linked.difference(routes)) {
    problems.add('sidebar links $href but no page generates it');
  }

  problems.sort();
  return problems;
}

Map<String, Object?> _indexPage(File file, String route) {
  final raw = file.readAsStringSync();
  final (:frontMatter, :body) = _splitFrontMatter(raw);

  final navItem = itemFor(route);
  // The page's own title, not the sidebar label: sidebar labels are shortened
  // to fit a 17rem column, and a search result should say what the page says.
  final title = frontMatter['title'] ?? navItem?.title ?? route;
  final description = navItem?.summary ?? frontMatter['description'] ?? '';

  return {
    'u': route,
    't': title,
    'd': description,
    'g': groupFor(route)?.title ?? '',
    's': _sectionsOf(body),
  };
}

/// Splits leading `---` YAML front matter from the markdown body.
///
/// Only the flat `key: value` pairs the docs actually use are read; anything
/// more structured is skipped rather than mis-parsed.
({Map<String, String> frontMatter, String body}) _splitFrontMatter(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---\n')) {
    return (frontMatter: const {}, body: normalized);
  }

  final end = normalized.indexOf('\n---', 3);
  if (end < 0) return (frontMatter: const {}, body: normalized);

  final block = normalized.substring(4, end);
  final body = normalized.substring(normalized.indexOf('\n', end + 1) + 1);

  final frontMatter = <String, String>{};
  String? key;
  final folded = StringBuffer();

  void flush() {
    final pending = key;
    if (pending != null && folded.isNotEmpty) {
      frontMatter[pending] = folded.toString().trim();
    }
    folded.clear();
  }

  for (final line in block.split('\n')) {
    final match = RegExp(r'^([A-Za-z_][\w-]*):\s*(.*)$').firstMatch(line);
    if (match != null) {
      flush();
      key = match.group(1);
      final value = match.group(2)!.trim();
      // `>-` / `|` introduce a folded block; its lines follow indented.
      folded.write(value == '>-' || value == '>' || value == '|' ? '' : _unquote(value));
    } else if (key != null && line.startsWith(RegExp(r'\s'))) {
      folded.write(' ${line.trim()}');
    }
  }
  flush();

  return (frontMatter: frontMatter, body: body);
}

String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

/// Splits a markdown body into `{h: heading, a: anchor, b: body}` records.
///
/// Text before the first heading becomes a leading section with no anchor, so
/// a page's intro is searchable too.
List<Map<String, Object?>> _sectionsOf(String body) {
  final sections = <Map<String, Object?>>[];
  var heading = '';
  var anchor = '';
  final buffer = StringBuffer();
  var inFence = false;

  void flush() {
    final text = _plainText(buffer.toString());
    buffer.clear();
    if (heading.isEmpty && text.isEmpty) return;
    sections.add({
      if (heading.isNotEmpty) 'h': heading,
      if (anchor.isNotEmpty) 'a': anchor,
      'b': text.length > _maxSectionLength ? text.substring(0, _maxSectionLength) : text,
    });
  }

  for (final line in body.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }

    // Headings inside a fenced block are shell comments, not sections.
    final match = inFence ? null : RegExp(r'^(#{2,3})\s+(.*)$').firstMatch(line);
    if (match == null) {
      buffer.writeln(line);
      continue;
    }

    flush();
    heading = _plainText(match.group(2)!);
    anchor = _anchorFor(match.group(2)!);
  }
  flush();

  return sections;
}

/// Reproduces the heading id that `package:markdown` generates.
///
/// `HeaderWithIdSyntax` hashes the *raw* inline text — before backticks, links
/// and emphasis are parsed — so `## Prefer \`zonai_client\`` becomes
/// `prefer-zonai_client`, not `prefer`. Matching that exactly is what lets a
/// search result deep-link to the right heading.
String _anchorFor(String rawHeading) => rawHeading
    .toLowerCase()
    .trim()
    .replaceAll(RegExp('[^a-z0-9 _-]'), '')
    .replaceAll(RegExp(r'\s'), '-');

/// Reduces markdown to searchable prose.
String _plainText(String markdown) {
  var text = markdown;

  // Component tags (<Info>, <CardGrid …>) and raw HTML carry no query terms.
  text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
  text = text.replaceAll(RegExp(r'</?[A-Za-z][\w-]*(\s[^<>]*)?/?>'), ' ');

  text = text.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!);
  text = text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!);

  text = text.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$', multiLine: true), '');
  text = text.replaceAll('|', ' ');
  // Underscores survive: `zonai_client` and `order_by` are things people search
  // for, and `_emphasis_` is not a style these docs use.
  text = text.replaceAll(RegExp(r'[`*#]'), '');

  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
