import 'package:revali_router/revali_router.dart';
import '../../lib/src/handlers/db_handler.dart';
import '../../lib/src/payloads/create_body.dart';
import '../../lib/src/payloads/delete_body.dart';
import '../../lib/src/payloads/get_body.dart';
import '../../lib/src/payloads/list_body.dart';
import '../../lib/src/payloads/stream_body.dart';
import '../../lib/src/payloads/stream_list_body.dart';
import '../../lib/src/payloads/update_body.dart';

// Learn more about Controllers at https://www.revali.dev/constructs/revali_server/core/controllers
@Controller('db')
class DbController {
  const DbController({required this.dbHandler});

  final DbHandler dbHandler;

  @Get()
  Future<Map<String, Object?>> get({@Body() required GetBody body}) async {
    return await dbHandler.get(body);
  }

  @Get('list')
  Future<Map<String, Object?>> list({@Body() required ListBody body}) async {
    return (await dbHandler.list(body)).toJson();
  }

  @Post()
  Future<Map<String, Object?>> create({
    @Body() required CreateBody body,
  }) async {
    return await dbHandler.create(body);
  }

  @Patch()
  Future<Map<String, Object?>> update({
    @Body() required UpdateOneBody body,
  }) async {
    return await dbHandler.update(body);
  }

  @Patch('many')
  Future<List<Map<String, Object?>>> updateMany({
    @Body() required UpdateBody body,
  }) async {
    return await dbHandler.updateMany(body);
  }

  @Delete()
  Future<void> delete({@Body() required DeleteOneBody body}) async {
    await dbHandler.delete(body);
  }

  @Delete('many')
  Future<void> deleteMany({@Body() required DeleteBody body}) async {
    await dbHandler.deleteMany(body);
  }

  @Get('stream')
  Stream<Map<String, Object?>> streamOne({@Body() required StreamBody body}) {
    return dbHandler.streamOne(body);
  }

  @Get('stream/list')
  Stream<List<Map<String, Object?>>> streamList({
    @Body() required StreamListBody body,
  }) {
    return dbHandler.streamList(body);
  }
}
