import 'package:zonai_schema/src/extension.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

class DbExtensions {
  const DbExtensions({required this.extensions});

  final List<Extension> extensions;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        return null;
      },
    ).listen();
  }
}
