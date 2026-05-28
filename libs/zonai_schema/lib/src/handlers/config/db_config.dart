import 'package:zonai_schema/src/config/app_config.dart';
import 'package:zonai_schema/src/handlers/config/config_request.dart';
import 'package:zonai_schema/src/handlers/config/config_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

class DbConfig {
  DbConfig({required this.config});

  final AppConfig config;

  void start() {
    MessageHandler(
      fromUnknownRequest: ConfigRequest.fromRequest,
      onMessage: (request) async {
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
