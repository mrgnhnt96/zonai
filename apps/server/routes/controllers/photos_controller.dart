import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_server/src/handlers/photo_handler.dart';

import '../components/black_list.dart';

// Learn more about Controllers at https://www.revali.dev/constructs/revali_server/core/controllers
@BlackList()
@Controller('img')
class PhotosController {
  const PhotosController({required this.photoHandler});

  final PhotoHandler photoHandler;

  @Get(':id')
  Future<Stream<List<int>>> view({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String id,
    required Headers responseHeaders,
  }) async {
    return await photoHandler.view(authorization, id, responseHeaders);
  }

  /// Upload an image: metadata in the query string, bytes in the request body.
  @Post()
  Future<Map<String, Object?>> create({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Header(HttpHeaders.contentTypeHeader) required String? contentType,
    @Query() required PhotoCreateMeta meta,
    @Body() required Stream<List<int>> image,
  }) async {
    return await photoHandler.create(authorization, meta, contentType, image);
  }

  @Patch(':id')
  Future<void> update({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String id,
    @Body() required Stream<List<int>> image,
  }) async {
    return await photoHandler.update(authorization, image, id);
  }

  @Delete()
  Future<void> delete({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String id,
  }) async {
    await photoHandler.delete(authorization, id);
  }
}
