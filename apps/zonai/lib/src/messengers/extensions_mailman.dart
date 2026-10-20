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
        warmRequestTimeout: requestTimeout,
      );

  static const debug = 'EXTENSIONS';

  /// Hooks are app code and routinely do I/O (sending mail, calling a
  /// third-party API), so the 1s default read ordinary hooks as a stuck
  /// worker. Seen on haymay: `afterCreateSuccess` timed out at 1s right
  /// after a deploy, and the admin was told a saved row had failed.
  static const requestTimeout = Duration(seconds: 10);
}
