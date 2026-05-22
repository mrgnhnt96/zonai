import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai_schema/src/handlers/config/config_request.dart';
import 'package:zonai_schema/src/handlers/config/config_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

final configResolverProvider = create<ConfigResolver>(ConfigResolver._);

ConfigResolver get configResolver => read(configResolverProvider);

class ConfigResolver {
  ConfigResolver({required Mailman<ConfigRequest, ConfigResponse> mailman})
    : _mailman = mailman;

  ConfigResolver._() : _mailman = null;

  final Mailman<ConfigRequest, ConfigResponse>? _mailman;

  Future<AppConfig> resolve() async {
    final mailman = _mailman;
    if (mailman == null) {
      throw Exception('Mailman not set');
    }

    final response = await mailman.send<GetAppConfigResponse>(
      GetAppConfigRequest(),
    );
    return response.data;
  }
}
