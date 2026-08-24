import '../ai_files.dart';
import '../ai_writer.dart';

Future<int> installCopilot() {
  for (final entry in aiToolFiles['copilot']!.entries) {
    writeAiFile(entry.key, entry.value);
  }
  return Future.value(0);
}
