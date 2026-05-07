import 'package:revali_router/revali_router.dart';
import '../../lib/src/handlers/db_handler.dart';

// Learn more about Controllers at https://www.revali.dev/constructs/revali_server/core/controllers
@Controller('db')
class DbController {
  const DbController({required this.dbHandler});

  final DbHandler dbHandler;

  @Get('one')
  void get() => dbHandler.get();

  @Get('list')
  Future<List<Map<String, Object?>>> list() async => await dbHandler.list();

  @Post()
  void create() => dbHandler.create();

  @Patch()
  void update() => dbHandler.update();

  @Patch('many')
  void updateMany() => dbHandler.updateMany();

  @Delete()
  void delete() => dbHandler.delete();
}
