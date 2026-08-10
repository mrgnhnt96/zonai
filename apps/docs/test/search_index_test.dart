/// Exercises the committed search index and the ranking that reads it.
///
/// These run against the real `web/search-index.json`, so a content change that
/// breaks search — a stale index, a heading anchor that no longer resolves, a
/// query that stops finding its page — fails here rather than in a browser.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_docs/src/navigation.dart';
import 'package:zonai_docs/src/search_index.dart';

void main() {
  final indexFile = File('web/search-index.json');

  late List<SearchDoc> index;

  setUpAll(() {
    expect(
      indexFile.existsSync(),
      isTrue,
      reason: 'Run: dart run tool/build_search_index.dart',
    );
    final payload = jsonDecode(indexFile.readAsStringSync()) as Map<String, Object?>;
    index = [
      for (final doc in payload['docs']! as List) SearchDoc.fromJson(doc as Map<String, Object?>),
    ];
  });

  group('index contents', () {
    test('covers every page in the sidebar', () {
      final indexed = {for (final doc in index) doc.url};
      final linked = {for (final item in flatNavigation) item.href};
      expect(linked.difference(indexed), isEmpty);
    });

    test('is current with content/', () {
      final result = Process.runSync('dart', ['run', 'tool/build_search_index.dart', '--check']);
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}${result.stderr}',
      );
    });

    test('keeps identifiers that people actually search for', () {
      final bodies = index.expand((doc) => doc.sections).map((section) => section.body).join(' ');
      // Markdown stripping must not eat underscores or dots out of API names.
      expect(bodies, contains('zonai_client'));
      expect(bodies, contains('db.listen'));
      expect(bodies, contains('order_by'));
    });

    test('every page contributes at least one searchable section', () {
      final empty = index.where((doc) => doc.sections.isEmpty).map((doc) => doc.url);
      expect(empty, isEmpty);
    });
  });

  group('ranking', () {
    /// The url of the top hit for [query].
    String top(String query) {
      final hits = searchIndex(index, query);
      expect(hits, isNotEmpty, reason: 'no hits for "$query"');
      return hits.first.href.split('#').first;
    }

    test('finds live queries by the words the docs use', () {
      expect(top('streaming'), '/operations/streaming');
      expect(top('db.listen'), '/operations/streaming');
      expect(top('live queries'), '/operations/streaming');
    });

    test('ranks the page about a topic above pages that mention it', () {
      expect(top('rate limit'), '/rate-limiting/overview');
      expect(top('migrations'), '/database/migrations-overview');
      expect(top('extensions'), '/extensions/overview');
    });

    test('finds pages by exact title', () {
      expect(top('quick start'), '/getting-started/quick-start');
      expect(top('trusted proxies'), '/rate-limiting/trusted-proxies');
      expect(top('cross-compilation'), '/deployment/cross-compilation');
      expect(top('fly.io'), '/deployment/fly-io');
    });

    test('finds pages by CLI command', () {
      expect(top('zonai db migrate'), startsWith('/'));
      expect(searchIndex(index, 'zonai db migrate').take(5).map((hit) => hit.href.split('#').first),
          contains('/cli/db'));
    });

    test('requires every token to match', () {
      // "streaming" matches many pages; "kubernetes" matches none, so the
      // conjunction must be empty rather than falling back to either term.
      expect(searchIndex(index, 'streaming kubernetes'), isEmpty);
    });

    test('returns no hits for an empty query', () {
      expect(searchIndex(index, ''), isEmpty);
      expect(searchIndex(index, '   '), isEmpty);
    });

    test('caps results and never returns more than three per page', () {
      final hits = searchIndex(index, 'the');
      expect(hits.length, lessThanOrEqualTo(24));

      final perPage = <String, int>{};
      for (final hit in hits) {
        final page = hit.href.split('#').first;
        perPage[page] = (perPage[page] ?? 0) + 1;
      }
      expect(perPage.values, everyElement(lessThanOrEqualTo(3)));
    });

    test('deep-links to a heading when the match is inside a section', () {
      final hit = searchIndex(index, 'trusted proxies').firstWhere(
        (hit) => hit.href.contains('#'),
        orElse: () => fail('expected at least one anchored hit'),
      );
      expect(hit.heading, isNotNull);
    });

    test('snippets surround the match rather than starting at the top', () {
      final hits = searchIndex(index, 'argon2id');
      expect(hits, isNotEmpty);
      expect(hits.first.snippet.toLowerCase(), contains('argon2id'));
    });
  });

  group('anchors', () {
    // Anchor generation reproduces `package:markdown`'s hashing by hand, so it
    // is checked against the actually-rendered HTML.
    final buildDir = Directory('build/jaspr');

    test('resolve to a real id in the built HTML', () {
      if (!buildDir.existsSync()) {
        markTestSkipped('No build/jaspr — run: dart run jaspr_cli:jaspr build');
        return;
      }

      final missing = <String>[];
      for (final doc in index) {
        final page = doc.url == '/'
            ? File('${buildDir.path}/index.html')
            : File('${buildDir.path}${doc.url}/index.html');
        if (!page.existsSync()) {
          missing.add('${doc.url} (no rendered page)');
          continue;
        }
        final html = page.readAsStringSync();
        for (final section in doc.sections) {
          if (section.anchor case final anchor?) {
            if (!html.contains('id="$anchor"')) {
              missing.add('${doc.url}#$anchor');
            }
          }
        }
      }

      expect(missing, isEmpty, reason: 'search results would deep-link to nothing');
    });
  });
}
