import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';
import 'package:zonai_schema/payloads.dart';

import '../components/black_list.dart';
import '../components/body_rate_limit.dart';
import '../components/custom_body_rate_limit.dart';
import '../components/query_rate_limit.dart';

// Learn more about Controllers at https://www.revali.dev/constructs/revali_server/core/controllers
@BlackList()
@Controller('db')
class DbController {
  const DbController({required this.dbHandler});

  final DbHandler dbHandler;

  @QueryRateLimit<GetBody>(.get)
  @Get()
  Future<Map<String, Object?>> get({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query() required GetBody body,
  }) async {
    return await dbHandler.get(authorization, body);
  }

  @QueryRateLimit<ListBody>(.list)
  @Get('list')
  Future<Map<String, Object?>> list({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query() required ListBody body,
  }) async {
    return (await dbHandler.list(authorization, body)).toJson();
  }

  @BodyRateLimit<CreateBody>(.create)
  @Post()
  Future<Map<String, Object?>> create({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required CreateBody body,
  }) async {
    return await dbHandler.create(authorization, body);
  }

  @BodyRateLimit<CreateManyBody>(.create)
  @Post('many')
  Future<List<Map<String, Object?>>> createMany({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required CreateManyBody body,
  }) async {
    return await dbHandler.createMany(authorization, body);
  }

  @BodyRateLimit<UpdateOneBody>(.update)
  @Patch()
  Future<Map<String, Object?>> update({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required UpdateOneBody body,
  }) async {
    return await dbHandler.update(authorization, body);
  }

  @BodyRateLimit<UpdateBody>(.update)
  @Patch('many')
  Future<List<Map<String, Object?>>> updateMany({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required UpdateBody body,
  }) async {
    return await dbHandler.updateMany(authorization, body);
  }

  @CustomBodyRateLimit<CustomOneBody>()
  @Patch('custom/:operation')
  Future<Map<String, Object?>> custom({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String operation,
    @Body() required CustomOneBody body,
  }) async {
    return await dbHandler.custom(authorization, operation, body);
  }

  @CustomBodyRateLimit<CustomBody>()
  @Patch('custom/:operation/many')
  Future<List<Map<String, Object?>>> customMany({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String operation,
    @Body() required CustomBody body,
  }) async {
    return await dbHandler.customMany(authorization, operation, body);
  }

  @BodyRateLimit<DeleteOneBody>(.delete)
  @Delete()
  Future<void> delete({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required DeleteOneBody body,
  }) async {
    await dbHandler.delete(authorization, body);
  }

  @BodyRateLimit<DeleteBody>(.delete)
  @Delete('many')
  Future<void> deleteMany({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required DeleteBody body,
  }) async {
    await dbHandler.deleteMany(authorization, body);
  }

  @QueryRateLimit<CountBody>(.count)
  @Get('count')
  Future<int> count({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query() required CountBody body,
  }) async {
    return await dbHandler.count(authorization, body);
  }

  @BodyRateLimit<StreamBody>(.get)
  @Get('stream')
  Stream<Map<String, Object?>> streamOne({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required StreamBody body,
  }) {
    return dbHandler.streamOne(authorization, body);
  }

  @BodyRateLimit<StreamListBody>(.list)
  @Get('stream/list')
  Stream<List<Map<String, Object?>>> streamList({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required StreamListBody body,
  }) {
    return dbHandler.streamList(authorization, body);
  }

  @BodyRateLimit<StreamCountBody>(.count)
  @Get('stream/count')
  Stream<int> streamCount({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required StreamCountBody body,
  }) {
    return dbHandler.streamCount(authorization, body);
  }
}
