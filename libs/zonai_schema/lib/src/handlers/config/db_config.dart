import 'package:zonai_schema/src/config/app_config.dart';
import 'package:zonai_schema/src/handlers/config/config_request.dart';
import 'package:zonai_schema/src/handlers/config/config_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

class DbConfig {
  DbConfig({required this.config});

  final AppConfig config;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        ConfigRequest request;
        try {
          request = ConfigRequest.fromRequest(msg);
        } catch (e, stack) {
          logger.debug(
            'Error handling request',
            properties: {'request': msg.toJson(), 'error': e.toString()},
          );
          return MessageErrorResponse(
            id: msg.id,
            message: 'Error handling request',
            error: e.toString(),
            stackTrace: stack.toString(),
          );
        }

        switch (request) {
          case final GetAppConfigRequest request:
            return await _getConfig(request);
        }
      },
    ).listen();
  }

  Future<GetAppConfigResponse> _getConfig(GetAppConfigRequest request) async {
    final data = await config;
    return GetAppConfigResponse(id: request.id, data: data);
  }
}
