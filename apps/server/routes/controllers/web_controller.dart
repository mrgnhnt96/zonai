import 'package:revali_router/revali_router.dart';

import '../components/black_list.dart';
import '../components/jaspr_web.dart';

@BlackList()
@Controller('_')
@JasprWeb()
class WebController {
  const WebController();

  @Get('*path')
  void get() {}
}
