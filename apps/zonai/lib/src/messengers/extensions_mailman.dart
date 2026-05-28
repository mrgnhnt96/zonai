import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';

class ExtensionsMailman extends Mailman<ExtensionRequest, ExtensionResponse> {
  ExtensionsMailman()
    : super(
        debugName: debug,
        executablePath: settings.compiledExtensionsPath,
        fromJson: ExtensionResponse.fromJson,
      );

  static const debug = 'EXTENSIONS';
}
