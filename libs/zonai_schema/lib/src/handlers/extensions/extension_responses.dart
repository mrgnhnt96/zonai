import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class ExtensionResponse extends Response {
  const ExtensionResponse({
    required super.path,
    required super.id,
    required super.payload,
  });
}
