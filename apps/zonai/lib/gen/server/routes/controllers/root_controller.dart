import 'package:revali_router/revali_router.dart';

@Controller('')
class RootController {
  const RootController();

  @Get('health')
  void health() {}
}
