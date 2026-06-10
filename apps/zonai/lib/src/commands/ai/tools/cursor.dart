import '../ai_templates.dart';
import '../ai_writer.dart';

Future<int> installCursor() {
  for (final entry in cursorMdcFiles.entries) {
    writeAiFile('.cursor/rules/${entry.key}', entry.value);
  }
  return Future.value(0);
}
