import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/zonai_schema.dart' show RateLimitOperation;

import '../components/black_list.dart';
import '../components/body_rate_limit.dart';
import '../components/custom_body_rate_limit.dart';
import '../components/query_rate_limit.dart';

// ! Spell the rate-limit operation out as `RateLimitOperation.x`, never as the
// dot-shorthand `.x`. Revali reads annotation arguments off an AST it does not
// always get resolved (revali/lib/server/utils/annotation_argument.dart), and a
// dot-shorthand is the one form that carries no fallback identifier -- when the
// AST comes back unresolved it degrades to InvalidType and server generation
// dies with "The argument expression has not been resolved yet". See
// docs/revali-dot-shorthand-codegen.md.

// Learn more about Controllers at https://www.revali.dev/constructs/revali_server/core/controllers
@BlackList()
@Controller('db')
class DbController {
  const DbController({required this.dbHandler});

  final DbHandler dbHandler;

  @QueryRateLimit<GetBody>(RateLimitOperation.get)
  @Get()
  Future<Map<String, Object?>> get({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query() required GetBody body,
  }) async {
    return await dbHandler.get(authorization, body);
  }

  @QueryRateLimit<ListBody>(RateLimitOperation.list)
  @Get('list')
  Future<Map<String, Object?>> list({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query() required ListBody body,
  }) async {
    return (await dbHandler.list(authorization, body)).toJson();
  }

  @BodyRateLimit<CreateBody>(RateLimitOperation.create)
  @Post()
  Future<Map<String, Object?>> create({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required CreateBody body,
  }) async {
    return await dbHandler.create(authorization, body);
  }

  @BodyRateLimit<CreateManyBody>(RateLimitOperation.create)
  @Post('many')
  Future<List<Map<String, Object?>>> createMany({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required CreateManyBody body,
  }) async {
    return await dbHandler.createMany(authorization, body);
  }

  @BodyRateLimit<UpdateOneBody>(RateLimitOperation.update)
  @Patch()
  Future<Map<String, Object?>> update({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required UpdateOneBody body,
  }) async {
    return await dbHandler.update(authorization, body);
  }

  @BodyRateLimit<UpdateBody>(RateLimitOperation.update)
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

  @BodyRateLimit<DeleteOneBody>(RateLimitOperation.delete)
  @Delete()
  Future<void> delete({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required DeleteOneBody body,
  }) async {
    await dbHandler.delete(authorization, body);
  }

  @BodyRateLimit<DeleteBody>(RateLimitOperation.delete)
  @Delete('many')
  Future<void> deleteMany({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required DeleteBody body,
  }) async {
    await dbHandler.deleteMany(authorization, body);
  }

  @QueryRateLimit<CountBody>(RateLimitOperation.count)
  @Get('count')
  Future<int> count({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query() required CountBody body,
  }) async {
    return await dbHandler.count(authorization, body);
  }

  @BodyRateLimit<StreamBody>(RateLimitOperation.get)
  @Get('stream')
  Stream<Map<String, Object?>> streamOne({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required StreamBody body,
  }) {
    return dbHandler.streamOne(authorization, body);
  }

  @BodyRateLimit<StreamListBody>(RateLimitOperation.list)
  @Get('stream/list')
  Stream<List<Map<String, Object?>>> streamList({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required StreamListBody body,
  }) {
    return dbHandler.streamList(authorization, body);
  }

  @BodyRateLimit<StreamCountBody>(RateLimitOperation.count)
  @Get('stream/count')
  Stream<int> streamCount({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required StreamCountBody body,
  }) {
    return dbHandler.streamCount(authorization, body);
  }
}
