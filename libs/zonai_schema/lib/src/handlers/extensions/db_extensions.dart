import 'package:zonai_schema/src/extension.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

class DbExtensions {
  const DbExtensions({required this.extensions});

  final List<Extension> extensions;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        ExtensionRequest request;
        try {
          request = ExtensionRequest.fromRequest(msg);
        } catch (e, stack) {
          logger.error(
            'Error handling extension request',
            error: '$e',
            stackTrace: stack.toString(),
            properties: {'request': msg.toJson()},
          );
          return MessageErrorResponse(
            id: msg.id,
            message: 'Error handling extension request',
            error: e.toString(),
            stackTrace: stack.toString(),
          );
        }

        logger.debug('___NOT HANDLED YET!!___');
        switch (request) {}
      },
    ).listen();
  }
}
