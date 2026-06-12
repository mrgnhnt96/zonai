import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/gen/swagger_assets.dart';

@Controller('')
class RootController {
  const RootController();

  @Get('health')
  void health() {}

  @Get('swagger.json')
  String swaggerJson({required Headers responseHeaders}) {
    responseHeaders.mimeType = 'application/json; charset=utf-8';
    return kSwaggerJson;
  }

  @Get('swagger.yaml')
  String swaggerYaml({required Headers responseHeaders}) {
    responseHeaders.mimeType = 'text/yaml; charset=utf-8';
    return kSwaggerYaml;
  }
}
