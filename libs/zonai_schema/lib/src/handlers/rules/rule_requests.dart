import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class RuleRequest extends Request {
  const RuleRequest({required super.path, required super.id});
}
