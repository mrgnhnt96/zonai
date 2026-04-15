import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class OperationResponse extends Response {
  const OperationResponse({
    required super.path,
    required super.id,
    required super.payload,
  });
}
