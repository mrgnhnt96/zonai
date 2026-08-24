import '../ai_files.dart';
import '../ai_writer.dart';

Future<int> installCursor() {
  for (final entry in aiToolFiles['cursor']!.entries) {
    writeAiFile(entry.key, entry.value);
  }
  return Future.value(0);
}
