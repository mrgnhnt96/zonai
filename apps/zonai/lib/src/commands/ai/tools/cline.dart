import '../ai_templates.dart';
import '../ai_writer.dart';

Future<int> installCline() {
  writeAiFile('.clinerules', clineRules);
  return Future.value(0);
}
