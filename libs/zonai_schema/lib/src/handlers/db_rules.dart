import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/zonai_schema.dart' show Rules;

class DbRules {
  const DbRules({required this.rules});

  final List<Rules> rules;

  void start() {
    MessageHandler(
      onMessage: (Request msg) async {
        return null;
      },
    ).listen();
  }
}
