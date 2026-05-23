import 'package:revali_router/revali_router.dart';

import '../components/jaspr_web.dart';

@Controller('_')
@JasprWeb()
class WebController {
  const WebController();

  @Get('*path')
  void get() {}
}
