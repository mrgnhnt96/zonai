import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

class DbOperations {
  const DbOperations({required this.operations});

  final List<CollectionOperations> operations;

  void start() {
    MessageHandler(
      onMessage: (Response msg) async {
        return null;
      },
    ).listen();
  }
}
