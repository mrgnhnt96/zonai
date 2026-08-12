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
// There is no baseline: every self-contained snippet compiles, and the #26
// backlog that once needed one is paid off. A snippet that is deliberately not
// compilable opts out by tagging its fence -- ```dart no-analyze -- which is
// visible in the diff of the doc that owns it, rather than as a hash in a list
// somewhere else. Adding one should be rare and should say why in the prose.
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

      final analysis = await _analyze(snippets, playground);
      final failures = analysis.failures;

      // Checked before the snippets themselves: a broken fixture makes every
      // snippet importing it fail for a reason that has nothing to do with the
      // docs, and those failures would be indistinguishable from real drift.
      expect(
        analysis.fixtureErrors,
        isEmpty,
        reason:
            'test/fixtures/doc_snippets no longer analyzes:\n'
            '  ${analysis.fixtureErrors.join('\n  ')}\n'
            'Fix the fixture. Nothing below this line can be trusted while a '
            'stand-in the snippets import is itself broken.',
      );

      expect(
        failures,
        isEmpty,
        reason:
            'These snippets no longer compile against the API they describe:\n'
            '${_render(failures)}\n'
            'Fix the snippet against the real API. If it is a sketch that is '
            'deliberately not compilable -- elided bodies, a placeholder '
            'import -- tag its fence ```dart no-analyze and say why in the '
            'prose around it. Do not reintroduce a baseline file.',
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

/// Runs the analyzer over [snippets] and maps each one to its errors.
///
/// They're written under the playground's `lib/` because the examples use the
/// relative imports of a real zonai project (`../schemas/items.dart`,
/// `../ids.dart`) -- imports that only resolve from inside one.
Future<({Map<_Snippet, List<String>> failures, List<String> fixtureErrors})>
_analyze(List<_Snippet> snippets, String playground) async {
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
    // Errors in the copied fixtures, which are not snippets and so are not
    // attributable to any doc. Left unreported they are worse than invisible:
    // a broken fixture takes down every snippet that imports it, and the pile
    // of resulting failures reads as doc drift rather than as one bad
    // stand-in.
    final fixtureErrors = <String>[];
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final parts = line.split('|');
      if (parts.length < 8) continue;
      if (parts[0] != 'ERROR') continue; // warnings/lints are not drift
      final snippet = byFile[p.basename(parts[3])];
      if (snippet == null) {
        final where = p.relative(parts[3], from: dir.path);
        fixtureErrors.add('$where:${parts[4]} ${parts[2]}: ${parts[7]}');
        continue;
      }
      failures
          .putIfAbsent(snippet, () => [])
          .add('${parts[2]} (snippet line ${parts[4]}): ${parts[7]}');
    }
    return (failures: failures, fixtureErrors: fixtureErrors);
  } finally {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// `my_app` is the docs' stand-in for the reader's own project. Point it at
/// the playground where the table really exists, and at a fixture where the
/// docs invented one.
String _resolve(String code) => code
    // The schema pages teach the `lib/src/ids.dart` that `zonai dev` writes.
    // It can't resolve to the playground's own ids.dart: that one carries the
    // playground's tables, not the `tasks`/`profiles`/`articles` the docs
    // invent, and the snippets that import it declare their own tables anyway.
    .replaceAll('package:my_app/src/ids.dart', 'fixtures/ids.dart')
    .replaceAllMapped(
      RegExp(r"package:my_app/src/schemas/(\w+)\.dart"),
      (m) => switch (m.group(1)!) {
        'users' ||
        'items' ||
        'posts' ||
        'authors' ||
        'companies' =>
          'package:zonai_playground/src/schemas/${m.group(1)}.dart',
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


String _render(Map<_Snippet, List<String>> failures) => failures.entries
    .map(
      (e) =>
          '  ${e.key}\n'
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
