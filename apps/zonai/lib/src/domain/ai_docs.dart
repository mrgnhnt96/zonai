/// The AI reference files `zonai ai` installs, and the version marker each one
/// carries.
///
/// The files are prose *about* this CLI -- schemas, rules, operations, rate
/// limits, crons -- copied into a consumer's project and committed there. They
/// go stale the moment the CLI moves, and until the stamp existed nothing in
/// the file said which release wrote it, so "is my CLAUDE.md current?" was not
/// a question anyone could answer. `zonai ai` also skips an existing file
/// without `--force`, which means an upgraded project keeps the old sheet and
/// is told only that the write was "Skipped".
///
/// The stamp lives *in* the file rather than in a sidecar (as
/// `native_library_stamp.dart` does for `.zonai/lib/`): these files are
/// committed to the consumer's repo and read by humans, and a `.stamp`
/// alongside `CLAUDE.md` would be one more unexplained file to review, one
/// that a copy/rename separates from the thing it describes. An HTML comment
/// travels with the content and renders as nothing.
library;

import 'package:file/file.dart';
import 'package:zonai/gen/version.dart';

import '../deps/fs.dart';

/// Where each tool's reference files land, relative to the project root.
///
/// This list is what a *scan* uses; the contents live with the templates in
/// `commands/ai/ai_files.dart`, and `ai_docs_paths_test.dart` pins the two
/// together. Nothing here imports a template, so the domain stays free of the
/// command layer.
const aiDocPaths = <String, List<String>>{
  'claude': ['CLAUDE.md'],
  'cursor': [
    '.cursor/rules/zonai-overview.mdc',
    '.cursor/rules/zonai-schemas.mdc',
    '.cursor/rules/zonai-operations.mdc',
    '.cursor/rules/zonai-rules.mdc',
    '.cursor/rules/zonai-views.mdc',
    '.cursor/rules/zonai-extensions.mdc',
    '.cursor/rules/zonai-rate-limits.mdc',
    '.cursor/rules/zonai-crons.mdc',
    '.cursor/rules/zonai-release.mdc',
  ],
  'copilot': ['.github/copilot-instructions.md'],
  'windsurf': ['.windsurfrules'],
  'cline': ['.clinerules'],
};

/// Every path any tool writes.
Iterable<String> get allAiDocPaths =>
    aiDocPaths.values.expand((paths) => paths);

const _marker = 'zonai:ai v';

/// Matches the marker anywhere in a file, so a stamp survives a user appending
/// their own notes underneath it.
final _stampPattern = RegExp('<!--\\s*$_marker([^\\s>]+)\\s*-->');

/// The line appended to every file `zonai ai` writes.
///
/// An HTML comment: invisible in rendered markdown, legal above and below the
/// YAML front matter the `.mdc` files open with, and -- deliberately -- not a
/// ```dart fence, which `doc_snippets_test.dart` would otherwise lift out of
/// `ai_templates.dart` and hand to the analyzer.
String aiDocStamp(String version) => '<!-- $_marker$version -->';

/// [contents] with the stamp for [version] appended.
String stampAiDoc(String contents, {String version = kVersion}) =>
    '${contents.trimRight()}\n\n${aiDocStamp(version)}\n';

/// The zonai version recorded in [contents], or `null` when it carries none.
///
/// The *last* marker wins: the stamp is appended, so a file quoting one in its
/// prose cannot outrank the real one.
String? readAiDocVersion(String contents) {
  final matches = _stampPattern.allMatches(contents);
  if (matches.isEmpty) return null;
  return matches.last.group(1);
}

/// An installed reference file, and the release that wrote it.
class AiDoc {
  const AiDoc({required this.path, required this.writtenBy});

  final String path;

  /// The version in the file's stamp, or `null` when it has none.
  ///
  /// Every file written before stamping existed is in that state, which is why
  /// an absent stamp reads as out of date rather than as current: the one
  /// thing it cannot mean is "written by the version running now".
  final String? writtenBy;

  bool isCurrent(String version) => writtenBy == version;

  String get describeWriter =>
      writtenBy == null ? 'no version stamp' : 'written by v$writtenBy';
}

/// The reference files this project actually has, in tool order.
///
/// A file that cannot be read is reported with a `null` [AiDoc.writtenBy]
/// rather than thrown out of: this drives a convenience prompt at the end of
/// an update that has already installed a binary, and an unreadable
/// `.clinerules` must not turn that into a crash.
List<AiDoc> installedAiDocs() {
  final docs = <AiDoc>[];

  for (final path in allAiDocPaths) {
    final File file;
    try {
      file = fs.file(path);
      if (!file.existsSync()) continue;
    } on FileSystemException {
      continue;
    }

    String? writtenBy;
    try {
      writtenBy = readAiDocVersion(file.readAsStringSync());
    } on FileSystemException {
      writtenBy = null;
    }

    docs.add(AiDoc(path: path, writtenBy: writtenBy));
  }

  return docs;
}

/// The installed reference files whose stamp does not name [version].
List<AiDoc> staleAiDocs({String version = kVersion}) => [
  for (final doc in installedAiDocs())
    if (!doc.isCurrent(version)) doc,
];
