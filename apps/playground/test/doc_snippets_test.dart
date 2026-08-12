// Compile-checks the ```dart examples in the prose docs and the `zonai ai`
// templates.
//
// Those examples are prose *about* an API, kept in sync by hand. #22 was one
// drifting the moment `zonai_schema` started re-exporting raindrop, with
// nothing connecting the two -- and the `ai_templates.dart` copies matter more
// than the docs, because `zonai ai` writes them straight into a consumer's
// project. `docs_views_test.dart` pins the one string that drifted then; this
// pins the *shape* of the bug by handing the snippets to the analyzer (#26).
//
// Only self-contained snippets (imports plus a top-level declaration) are
// checked. The remaining ~200 fences are fragments -- a bare `@override`
// member, a few statements -- which need a scaffold that says which class or
// function body they belong in. Nothing here checks those, and nothing here
// checks a snippet's *behavior*: it compiles or it doesn't.
//
// Snippets that don't analyze today are listed in `doc_snippets_baseline.txt`,
// keyed by content hash so editing one forces it to be fixed or re-listed.
// This test fails when a snippet outside that list breaks, and equally when a
// listed one starts passing -- the list only ever shrinks.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = _workspaceRoot();
  final playground = p.join(root, 'apps', 'playground');

  test(
    'every self-contained doc snippet analyzes',
    () async {
      final snippets = _collect(root).where((s) => s.isSelfContained).toList();

      expect(
        snippets,
        isNotEmpty,
        reason:
            'Found no self-contained snippets at all -- the extractor stopped '
            'matching the docs rather than the docs losing their examples.',
      );

      final failures = await _analyze(snippets, playground);
      final baseline = _readBaseline(root);

      final present = {for (final s in snippets) s.id};
      final failing = {for (final f in failures.keys) f.id};

      final unexpected = {
        for (final e in failures.entries)
          if (!baseline.contains(e.key.id)) e.key: e.value,
      };
      // Two ways a line stops earning its place: the snippet it names now
      // compiles, or it no longer names a snippet at all (someone edited the
      // example, which changes its content-addressed key). Both are stale.
      final stale = baseline.difference(failing);

      expect(
        unexpected,
        isEmpty,
        reason:
            'These snippets no longer compile against the API they describe:\n'
            '${_render(unexpected)}\n'
            'Fix the snippet, or -- if it is deliberately incomplete -- add its '
            'key to apps/playground/test/doc_snippets_baseline.txt with a note '
            'saying why.',
      );

      expect(
        stale,
        isEmpty,
        reason:
            'These doc_snippets_baseline.txt lines no longer excuse anything '
            '-- the snippet compiles now, or it was edited and no longer has '
            'this key:\n  ${stale.map((k) => '$k${present.contains(k) ? ' (compiles now)' : ' (no such snippet)'}').join('\n  ')}\n'
            'Delete them. A baseline that keeps entries it no longer needs '
            'stops being evidence of anything.',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// A ```dart fence lifted out of a markdown file (or out of the markdown
/// embedded in `ai_templates.dart`'s string literals).
class _Snippet {
  _Snippet({required this.source, required this.line, required this.code});

  final String source;
  final int line;
  final String code;

  /// Keyed by content, not by line: editing a snippet changes its key, so a
  /// baselined snippet can't be quietly rewritten and stay excused.
  late final String id = '$source#${_fnv1a(code)}';

  bool get _hasImports =>
      code.contains(RegExp(r'^\s*import ', multiLine: true));

  bool get _hasTopLevelDecl => RegExp(
    r'^(final class|class|abstract class|base class|enum|mixin|extension|'
    r'void main|[A-Za-z_<>, ?]+ main\()',
    multiLine: true,
  ).hasMatch(code);

  /// Enough of a file to stand on its own. Anything else is a fragment whose
  /// missing context we'd have to invent, which would test the invention.
  bool get isSelfContained => _hasImports && _hasTopLevelDecl;

  @override
  String toString() => '$source:$line';
}

/// FNV-1a, so a snippet's key is stable across runs and SDK versions without
/// pulling in a hashing dependency for it.
String _fnv1a(String input) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(input)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Runs the analyzer over [snippets] and maps each one to its errors.
///
/// They're written under the playground's `lib/` because the examples use the
/// relative imports of a real zonai project (`../schemas/items.dart`,
/// `../ids.dart`) -- imports that only resolve from inside one.
Future<Map<_Snippet, List<String>>> _analyze(
  List<_Snippet> snippets,
  String playground,
) async {
  final dir = Directory(p.join(playground, 'lib', 'src', '__doc_snippets__'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  try {
    final fixtures = Directory(
      p.join(playground, 'test', 'fixtures', 'doc_snippets'),
    );
    final fixtureDir = Directory(p.join(dir.path, 'fixtures'))
      ..createSync(recursive: true);
    for (final f in fixtures.listSync().whereType<File>()) {
      f.copySync(p.join(fixtureDir.path, p.basename(f.path)));
    }

    final byFile = <String, _Snippet>{};
    for (var i = 0; i < snippets.length; i++) {
      final name = 'snippet_$i.dart';
      File(
        p.join(dir.path, name),
      ).writeAsStringSync(_resolve(snippets[i].code));
      byFile[name] = snippets[i];
    }

    final result = await Process.run('dart', [
      'analyze',
      '--format',
      'machine',
      dir.path,
    ], workingDirectory: playground);

    final failures = <_Snippet, List<String>>{};
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final parts = line.split('|');
      if (parts.length < 8) continue;
      if (parts[0] != 'ERROR') continue; // warnings/lints are not drift
      final snippet = byFile[p.basename(parts[3])];
      if (snippet == null) continue;
      failures
          .putIfAbsent(snippet, () => [])
          .add('${parts[2]} (snippet line ${parts[4]}): ${parts[7]}');
    }
    return failures;
  } finally {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// `my_app` is the docs' stand-in for the reader's own project. Point it at
/// the playground where the table really exists, and at a fixture where the
/// docs invented one.
String _resolve(String code) => code.replaceAllMapped(
  RegExp(r"package:my_app/src/schemas/(\w+)\.dart"),
  (m) => switch (m.group(1)!) {
    'users' ||
    'items' ||
    'posts' ||
    'authors' ||
    'companies' => 'package:zonai_playground/src/schemas/${m.group(1)}.dart',
    final other => 'fixtures/$other.dart',
  },
);

Iterable<_Snippet> _collect(String root) sync* {
  for (final f in Directory(
    p.join(root, 'docs'),
  ).listSync().whereType<File>()) {
    if (f.path.endsWith('.md')) yield* _fences(root, f);
  }

  final content = Directory(p.join(root, 'apps', 'docs', 'content'));
  if (content.existsSync()) {
    for (final f in content.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.md')) yield* _fences(root, f);
    }
  }

  // The AI templates are Dart string literals holding markdown holding dart
  // fences. Reading them as text finds the fences without running the CLI.
  yield* _fences(
    root,
    File(
      p.join(
        root,
        'apps',
        'zonai',
        'lib',
        'src',
        'commands',
        'ai',
        'ai_templates.dart',
      ),
    ),
  );
}

List<_Snippet> _fences(String root, File file) {
  final source = p.relative(file.path, from: root);
  final lines = const LineSplitter().convert(file.readAsStringSync());
  final out = <_Snippet>[];

  for (var i = 0; i < lines.length; i++) {
    // Only bare ```dart -- an info string (```dart title="x") marks a fence
    // the author has already annotated for some other purpose.
    if (lines[i].trim() != '```dart') continue;
    final body = <String>[];
    var j = i + 1;
    for (; j < lines.length && lines[j].trim() != '```'; j++) {
      body.add(lines[j]);
    }
    out.add(_Snippet(source: source, line: i + 1, code: body.join('\n')));
    i = j;
  }
  return out;
}

Set<String> _readBaseline(String root) {
  final file = File(
    p.join(root, 'apps', 'playground', 'test', 'doc_snippets_baseline.txt'),
  );
  if (!file.existsSync()) return {};
  return {
    for (final line in const LineSplitter().convert(file.readAsStringSync()))
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
        line.trim(),
  };
}

String _render(Map<_Snippet, List<String>> failures) => failures.entries
    .map(
      (e) =>
          '  ${e.key} (${e.key.id})\n'
          '${e.value.map((m) => '      $m').join('\n')}',
    )
    .join('\n');

String _workspaceRoot() {
  final configFile = File(Uri.parse(Platform.packageConfig!).toFilePath());
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

  for (final raw in config['packages'] as List<dynamic>) {
    final pkg = raw as Map<String, dynamic>;
    if (pkg['name'] != 'zonai_workspace') continue;
    return p.normalize(
      p.join(p.dirname(configFile.absolute.path), pkg['rootUri'] as String),
    );
  }

  throw StateError(
    'Package "zonai_workspace" not found in ${Platform.packageConfig}',
  );
}
