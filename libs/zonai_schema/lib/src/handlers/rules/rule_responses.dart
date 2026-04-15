import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class RuleResponse extends Response {
  const RuleResponse({
    required super.path,
    required super.id,
    required super.payload,
  });
}
