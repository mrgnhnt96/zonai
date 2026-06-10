import 'dart:io';

import '../../deps/args.dart';
import '../../deps/fs.dart';

void writeAiFile(String path, String contents) {
  final force = args.getOrNull<bool>('force', abbr: 'f') == true;
  final file = fs.file(path);

  if (file.existsSync() && !force) {
    stdout.writeln('Skipped $path (use --force to overwrite)');
    return;
  }

  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  stdout.writeln('Created $path');
}
