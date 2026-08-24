import 'dart:io';

import 'package:file/file.dart';

import '../../deps/args.dart';
import '../../deps/fs.dart';
import '../../domain/ai_docs.dart';

/// Writes one AI reference file, stamped with the version that wrote it.
///
/// [force] overrides the `--force` flag for callers that already decided --
/// `zonai ai update` refreshes files it has just confirmed are there, which is
/// not the same request as `--force`'s "install over whatever is present".
void writeAiFile(String path, String contents, {bool? force}) {
  final forced = force ?? (args.getOrNull<bool>('force', abbr: 'f') == true);
  final file = fs.file(path);
  final existed = file.existsSync();

  if (existed && !forced) {
    // Naming the version turns a skip into an answer: "Skipped CLAUDE.md" left
    // an upgraded project unable to tell an up-to-date sheet from a stale one.
    stdout.writeln(
      'Skipped $path (${_writerOf(file)}, use --force to overwrite)',
    );
    return;
  }

  file.parent.createSync(recursive: true);
  file.writeAsStringSync(stampAiDoc(contents));
  stdout.writeln('${existed ? 'Updated' : 'Created'} $path');
}

String _writerOf(File file) {
  try {
    return AiDoc(
      path: file.path,
      writtenBy: readAiDocVersion(file.readAsStringSync()),
    ).describeWriter;
  } on FileSystemException {
    return 'unreadable';
  }
}
