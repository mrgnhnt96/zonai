import '../ai_files.dart';
import '../ai_writer.dart';

Future<int> installWindsurf() {
  for (final entry in aiToolFiles['windsurf']!.entries) {
    writeAiFile(entry.key, entry.value);
  }
  return Future.value(0);
}
