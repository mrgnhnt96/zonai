import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

// Learn more about Controllers at https://www.revali.dev/constructs/revali_server/core/controllers
@Controller('db')
class DbController {
  const DbController({required this.dbHandler});

  final DbHandler dbHandler;

  @Get()
  Future<Map<String, Object?>> get({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query() required GetBody body,
  }) async {
    return await dbHandler.get(authorization, body);
  }

  @Get('list')
  Future<Map<String, Object?>> list({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query() required ListBody body,
  }) async {
    return (await dbHandler.list(authorization, body)).toJson();
  }

  @Post()
  Future<Map<String, Object?>> create({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required CreateBody body,
  }) async {
    return await dbHandler.create(authorization, body);
  }

  @Patch()
  Future<Map<String, Object?>> update({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required UpdateOneBody body,
  }) async {
    return await dbHandler.update(authorization, body);
  }

  @Patch('many')
  Future<List<Map<String, Object?>>> updateMany({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required UpdateBody body,
  }) async {
    return await dbHandler.updateMany(authorization, body);
  }

  @Delete()
  Future<void> delete({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required DeleteOneBody body,
  }) async {
    await dbHandler.delete(authorization, body);
  }

  @Delete('many')
  Future<void> deleteMany({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required DeleteBody body,
  }) async {
    await dbHandler.deleteMany(authorization, body);
  }

  @Get('stream')
  Stream<Map<String, Object?>> streamOne({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required StreamBody body,
  }) {
    return dbHandler.streamOne(authorization, body);
  }

  @Get('stream/list')
  Stream<List<Map<String, Object?>>> streamList({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required StreamListBody body,
  }) {
    return dbHandler.streamList(authorization, body);
  }
}
