import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_server/gen/swagger_assets.dart';
import 'package:revali_swagger_annotations/revali_swagger_annotations.dart'
    as swagger;

@Controller('')
class RootController {
  const RootController();

  @Get('health')
  void health() {}

  @swagger.ApiHidden()
  @Get('favicon.ico')
  Future<Stream<List<int>>> favicon({required Headers responseHeaders}) async {
    final file = fs.file(fs.path.join(settings.imagesPath, 'favicon.ico'));
    if (!file.existsSync()) {
      throw const PhotoFileNotFoundException();
    }
    responseHeaders.mimeType = 'image/x-icon';
    responseHeaders.set(HttpHeaders.contentDisposition, 'inline');
    return file.openRead();
  }

  /// Optional brand mark for the dashboard. Unlike [favicon], nothing seeds
  /// this file -- its absence is what selects the letter-tile fallback, so a
  /// 404 here is the normal case, not an error.
  @swagger.ApiHidden()
  @Get('logo.png')
  Future<Stream<List<int>>> logo({required Headers responseHeaders}) async {
    final file = fs.file(fs.path.join(settings.imagesPath, 'logo.png'));
    if (!file.existsSync()) {
      throw const PhotoFileNotFoundException();
    }
    responseHeaders.mimeType = 'image/png';
    responseHeaders.set(HttpHeaders.contentDisposition, 'inline');
    return file.openRead();
  }

  @Get('swagger.json')
  StringContent swaggerJson({required Headers responseHeaders}) {
    responseHeaders.mimeType = 'application/json; charset=utf-8';
    return StringContent(kSwaggerJson);
  }

  @Get('swagger.yaml')
  StringContent swaggerYaml({required Headers responseHeaders}) {
    responseHeaders.mimeType = 'text/yaml; charset=utf-8';
    return StringContent(kSwaggerYaml);
  }
}
