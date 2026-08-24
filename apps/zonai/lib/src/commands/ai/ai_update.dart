import 'dart:io';

import '../../domain/ai_docs.dart';
import 'ai_files.dart';
import 'ai_writer.dart';

/// Rewrites the reference files this project already has, in place.
///
/// Deliberately not `ai all --force`: that writes a file for every supported
/// tool, so refreshing a stale `CLAUDE.md` would also drop `.windsurfrules`,
/// `.clinerules` and a nine-file `.cursor/rules/` directory into a project
/// that never asked for any of them. Refreshing is not installing.
Future<int> updateInstalledAiFiles() async {
  final installed = {for (final doc in installedAiDocs()) doc.path};

  if (installed.isEmpty) {
    stdout.writeln(
      'No AI reference files found. Run `zonai ai all` to install them.',
    );
    return 0;
  }

  for (final entry in aiToolFiles.values.expand((files) => files.entries)) {
    if (!installed.contains(entry.key)) continue;
    writeAiFile(entry.key, entry.value, force: true);
  }

  return 0;
}
