import '../ai_templates.dart';
import '../ai_writer.dart';

Future<int> installWindsurf() {
  writeAiFile('.windsurfrules', windsurfRules);
  return Future.value(0);
}
