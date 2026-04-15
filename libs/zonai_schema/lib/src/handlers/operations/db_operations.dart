import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/operation_requests.dart';
import 'package:zonai_schema/zonai_schema.dart' hide Request;

class DbOperations {
  const DbOperations({required this.operations});

  final List<CollectionOperations> operations;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        final request = OperationRequest.fromRequest(msg);
      },
    ).listen();
  }
}
