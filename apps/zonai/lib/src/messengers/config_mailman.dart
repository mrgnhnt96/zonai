import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai_schema/src/handlers/config/config_request.dart';
import 'package:zonai_schema/src/handlers/config/config_response.dart';

class ConfigMailman extends Mailman<ConfigRequest, ConfigResponse> {
  ConfigMailman()
    : super(
        debugName: debug,
        executablePath: settings.compiledConfigPath,
        fromJson: ConfigResponse.fromJson,
      );

  static const debug = 'CONFIG';
}
