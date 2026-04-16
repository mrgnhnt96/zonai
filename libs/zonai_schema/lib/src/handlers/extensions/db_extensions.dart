import 'package:zonai_schema/src/extension.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

class DbExtensions {
  const DbExtensions({required this.extensions});

  final List<Extension> extensions;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        final request = ExtensionRequest.fromRequest(msg);
      },
    ).listen();
  }
}
