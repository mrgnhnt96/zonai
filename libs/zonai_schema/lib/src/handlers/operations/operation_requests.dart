import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class OperationRequest extends Request {
  const OperationRequest({required super.path, required super.id});

  factory OperationRequest.fromRequest(UnknownRequest request) {
    throw UnimplementedError();
  }
}
