/// Structural checks on the sidebar's information architecture.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_docs/src/navigation.dart';

void main() {
  test('every link points at a page that exists', () {
    final missing = [
      for (final item in flatNavigation)
        if (!File('content${item.href == '/' ? '/index' : item.href}.md').existsSync()) item.href,
    ];
    expect(missing, isEmpty);
  });

  test('every page is reachable from the sidebar', () {
    final linked = {for (final item in flatNavigation) item.href};
    final orphans = <String>[];

    for (final file in Directory('content').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.md')) continue;
      var route = file.path.substring('content'.length).replaceFirst(RegExp(r'\.md$'), '');
      if (route == '/index') route = '/';
      if (!linked.contains(route) && !unlistedRoutes.contains(route)) orphans.add(route);
    }

    expect(orphans, isEmpty, reason: 'add these to lib/src/navigation.dart or unlistedRoutes');
  });

  test('no page is listed twice', () {
    final seen = <String>{};
    final duplicates = [
      for (final item in flatNavigation)
        if (!seen.add(item.href)) item.href,
    ];
    expect(duplicates, isEmpty);
  });

  test('groups are non-empty and titled', () {
    for (final group in navigation) {
      expect(group.items, isNotEmpty, reason: group.title);
      expect(group.title.trim(), isNotEmpty);
      expect(group.icon, startsWith('<svg'), reason: group.title);
    }
  });

  test('prev/next spans the whole reading order exactly once', () {
    final flat = flatNavigation;
    expect(neighborsOf(flat.first.href).previous, isNull);
    expect(neighborsOf(flat.last.href).next, isNull);

    // Walking `next` from the first page must visit every page in order.
    final walked = <String>[flat.first.href];
    var current = neighborsOf(flat.first.href).next;
    while (current != null) {
      walked.add(current.href);
      current = neighborsOf(current.href).next;
    }
    expect(walked, flat.map((item) => item.href).toList());
  });
}
