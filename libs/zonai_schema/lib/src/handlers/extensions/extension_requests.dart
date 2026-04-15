import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class ExtensionRequest extends Request {
  const ExtensionRequest({required super.path, required super.id});
}
