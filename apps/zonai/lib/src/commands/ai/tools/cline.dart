import '../ai_files.dart';
import '../ai_writer.dart';

Future<int> installCline() {
  for (final entry in aiToolFiles['cline']!.entries) {
    writeAiFile(entry.key, entry.value);
  }
  return Future.value(0);
}
