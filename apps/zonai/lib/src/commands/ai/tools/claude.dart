import '../ai_files.dart';
import '../ai_writer.dart';

Future<int> installClaude() {
  for (final entry in aiToolFiles['claude']!.entries) {
    writeAiFile(entry.key, entry.value);
  }
  return Future.value(0);
}
