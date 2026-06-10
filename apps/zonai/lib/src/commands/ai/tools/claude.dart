import '../ai_templates.dart';
import '../ai_writer.dart';

Future<int> installClaude() {
  writeAiFile('CLAUDE.md', claudeMd);
  return Future.value(0);
}
