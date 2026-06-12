import 'package:revali_client/revali_client.dart';
import 'package:revali_router/revali_router.dart';
import 'package:revali_swagger_annotations/revali_swagger_annotations.dart'
    as swagger;

import '../components/black_list.dart';
import '../components/jaspr_web.dart';

@ExcludeFromClient()
@swagger.ApiHidden()
@BlackList()
@Controller('_')
@JasprWeb()
class WebController {
  const WebController();

  @Get('*path')
  void get() {}
}
