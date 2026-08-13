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
// Two kinds of fence are checked. A self-contained one (imports plus a
// top-level declaration) is analyzed as written. A *fragment* -- a bare
// `@override` member, a few loose statements -- names the surrounding code it
// belongs in on its fence:
//
//     ```dart in:extension-user
//     @override
//     Future<void> onSignUp(User user, Jwt? jwt) async { ... }
//     ```
//
// `in:<name>` resolves to test/fixtures/doc_scaffolds/<name>.dart, a real Dart
// file with a `// <<body>>` marker where the fragment is spliced. The scaffolds
// are analyzed empty as well, so one that rots against the API fails as itself
// rather than as a pile of unexplained snippet errors.
//
// There is no baseline. A fence that is deliberately not compilable opts out
// with ```dart no-analyze, which is visible in the diff of the doc that owns it
// rather than as a hash in a list somewhere else, and should say why in the
// prose beside it.
//
// What this still does not do: it does not know whether an example is
// *correct*, only that it compiles. The ownership check comparing an `Id` to a
// `String`, and the photo API documented under the wrong route, both compiled.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = _workspaceRoot();
  final playground = p.join(root, 'apps', 'playground');

  test(
    'every checkable doc snippet analyzes',
    () async {
      // A fence naming a scaffold that does not exist is left to the test
      // below, which says so in one line rather than as a crash here.
      final scaffolds = _scaffoldNames(playground);
      final snippets = _collect(root)
          .where((s) => s.isCheckable)
          .where((s) => s.scaffold == null || scaffolds.contains(s.scaffold))
          .toList();

      expect(
        snippets,
        isNotEmpty,
        reason:
            'Found no checkable snippets at all -- the extractor stopped '
            'matching the docs rather than the docs losing their examples.',
      );

      final analysis = await _analyze(snippets, playground);
      final failures = analysis.failures;

      // Checked before the snippets, for the same reason as the fixtures: a
      // scaffold that no longer compiles takes down every fragment spliced
      // into it, and those failures would read as drift in a dozen docs at
      // once rather than as one stale scaffold.
      expect(
        analysis.scaffoldErrors,
        isEmpty,
        reason:
            'test/fixtures/doc_scaffolds no longer analyzes:\n'
            '  ${analysis.scaffoldErrors.join('\n  ')}\n'
            'Fix the scaffold against the real API. Nothing below this line '
            'can be trusted while the surrounding code a fragment is spliced '
            'into is itself broken.',
      );

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

  test('every in: tag names a scaffold that exists', () {
    final scaffolds = _scaffoldNames(playground);
    final unknown = <String>[];

    for (final s in _collect(root)) {
      if (s.scaffold case final name? when !scaffolds.contains(name)) {
        unknown.add('$s -> in:$name');
      }
    }

    expect(
      unknown,
      isEmpty,
      reason:
          'These fences name a scaffold that does not exist:\n'
          '  ${unknown.join('\n  ')}\n'
          'Available: ${(scaffolds.toList()..sort()).join(', ')}\n'
          'Add the scaffold under test/fixtures/doc_scaffolds/ (a real Dart '
          'file with a `// <<body>>` marker) or point the fence at one that '
          'is already there. A typo here would otherwise skip the fragment '
          'silently, which is the failure mode this whole test exists to '
          'remove.',
    );
  });

  // Still to come: the gate that no fence escapes unchecked. It belongs with
  // the sweep that tags the ~200 fragments, not ahead of it -- a guard whose
  // only output is the work it is waiting on teaches everyone to ignore it.
}

/// A ```dart fence lifted out of a markdown file (or out of the markdown
/// embedded in `ai_templates.dart`'s string literals).
class _Snippet {
  _Snippet({
    required this.source,
    required this.line,
    required this.code,
    required this.info,
  });

  final String source;
  final int line;
  final String code;

  /// The fence's info string after the language -- `in:row-rules`,
  /// `no-analyze`, or empty for a bare ```dart fence.
  final String info;

  /// The scaffold this fragment is spliced into, or null if it stands alone.
  String? get scaffold =>
      info.startsWith('in:') ? info.substring(3).trim() : null;

  /// Opted out at the fence, with the reason in the prose beside it.
  bool get skipped => info == 'no-analyze';

  bool get _hasImports =>
      code.contains(RegExp(r'^\s*import ', multiLine: true));

  bool get _hasTopLevelDecl => RegExp(
    r'^(final class|class|abstract class|base class|enum|mixin|extension|'
    r'void main|[A-Za-z_<>, ?]+ main\()',
    multiLine: true,
  ).hasMatch(code);

  /// Enough of a file to stand on its own.
  bool get isSelfContained => _hasImports && _hasTopLevelDecl;

  /// Analyzable: either it stands alone, or its fence says what it belongs in.
  bool get isCheckable => scaffold != null || (info.isEmpty && isSelfContained);

  @override
  String toString() => '$source:$line';
}

/// Runs the analyzer over [snippets] and maps each one to its errors.
///
/// They're written under the playground's `lib/` because the examples use the
/// relative imports of a real zonai project (`../schemas/items.dart`,
/// `../ids.dart`) -- imports that only resolve from inside one.
Future<
  ({
    Map<_Snippet, List<String>> failures,
    List<String> fixtureErrors,
    List<String> scaffoldErrors,
  })
>
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
    // How many scaffold lines sit above the fragment in each generated file,
    // so a reported line can be given back in the doc's own terms.
    final offsets = <String, int>{};
    // Each scaffold spliced with an empty body, analyzed alongside the
    // snippets so scaffold rot is reported once, as itself.
    final scaffoldFiles = <String, String>{};

    for (var i = 0; i < snippets.length; i++) {
      final snippet = snippets[i];
      final name = 'snippet_$i.dart';

      if (snippet.scaffold case final scaffold?) {
        final template = _scaffold(playground, scaffold);
        final (:code, :offset) = _splice(template, snippet.code);
        File(p.join(dir.path, name)).writeAsStringSync(_resolve(code));
        offsets[name] = offset;

        final probe = 'scaffold_$scaffold.dart';
        scaffoldFiles.putIfAbsent(probe, () {
          File(
            p.join(dir.path, probe),
          ).writeAsStringSync(_resolve(_splice(template, '').code));
          return scaffold;
        });
      } else {
        File(p.join(dir.path, name)).writeAsStringSync(_resolve(snippet.code));
      }

      byFile[name] = snippet;
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
    final scaffoldErrors = <String>[];
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final parts = line.split('|');
      if (parts.length < 8) continue;
      if (parts[0] != 'ERROR') continue; // warnings/lints are not drift
      final file = p.basename(parts[3]);

      if (scaffoldFiles[file] case final scaffold?) {
        scaffoldErrors.add('$scaffold.dart: ${parts[2]}: ${parts[7]}');
        continue;
      }

      final snippet = byFile[file];
      if (snippet == null) {
        final where = p.relative(parts[3], from: dir.path);
        fixtureErrors.add('$where:${parts[4]} ${parts[2]}: ${parts[7]}');
        continue;
      }

      final reported = int.tryParse(parts[4]) ?? 0;
      final within = reported - (offsets[file] ?? 0);
      failures
          .putIfAbsent(snippet, () => [])
          .add('${parts[2]} (snippet line $within): ${parts[7]}');
    }
    return (
      failures: failures,
      fixtureErrors: fixtureErrors,
      scaffoldErrors: scaffoldErrors,
    );
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
        'users' || 'items' || 'posts' || 'authors' || 'companies' =>
          'package:zonai_playground/src/schemas/${m.group(1)}.dart',
        final other => 'fixtures/$other.dart',
      },
    );

/// The marker a scaffold puts where the fragment goes.
const _bodyMarker = '// <<body>>';

Directory _scaffoldDir(String playground) =>
    Directory(p.join(playground, 'test', 'fixtures', 'doc_scaffolds'));

Set<String> _scaffoldNames(String playground) {
  final dir = _scaffoldDir(playground);
  if (!dir.existsSync()) return const {};
  return {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.dart')) p.basenameWithoutExtension(f.path),
  };
}

String _scaffold(String playground, String name) => File(
  p.join(_scaffoldDir(playground).path, '$name.dart'),
).readAsStringSync();

/// Puts [body] where the scaffold's marker is, reporting how many lines ended
/// up above it so an analyzer line can be translated back to the fence.
({String code, int offset}) _splice(String template, String body) {
  final lines = const LineSplitter().convert(template);
  final at = lines.indexWhere((l) => l.trim() == _bodyMarker);

  if (at < 0) {
    throw StateError(
      'Scaffold has no `$_bodyMarker` marker, so there is nowhere to put the '
      'fragment.',
    );
  }

  return (
    code: [...lines.take(at), body, ...lines.skip(at + 1)].join('\n'),
    offset: at,
  );
}

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
    final fence = lines[i].trim();

    // A ````-fenced block quotes a fence literally -- it is how a doc shows
    // what a ```dart fence looks like. Reading the example inside one as a
    // real snippet made this test try to analyze its own documentation.
    if (RegExp(r'^`{4,}').hasMatch(fence)) {
      final close = RegExp('^${fence.substring(0, 4)}`*\$');
      var j = i + 1;
      while (j < lines.length && !close.hasMatch(lines[j].trim())) {
        j++;
      }
      i = j;
      continue;
    }

    if (fence != '```dart' && !fence.startsWith('```dart ')) continue;

    final body = <String>[];
    var j = i + 1;
    for (; j < lines.length && lines[j].trim() != '```'; j++) {
      body.add(lines[j]);
    }
    out.add(
      _Snippet(
        source: source,
        line: i + 1,
        code: body.join('\n'),
        info: fence.substring('```dart'.length).trim(),
      ),
    );
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
