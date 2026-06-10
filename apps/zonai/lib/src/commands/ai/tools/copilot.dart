import '../ai_templates.dart';
import '../ai_writer.dart';

Future<int> installCopilot() {
  writeAiFile('.github/copilot-instructions.md', copilotMd);
  return Future.value(0);
}
