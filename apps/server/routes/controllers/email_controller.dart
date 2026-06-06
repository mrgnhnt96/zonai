import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/email_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../components/black_list.dart';

@BlackList()
@Controller('email')
class EmailController {
  const EmailController({required this.emailHandler});

  final EmailHandler emailHandler;

  @Post()
  Future<void> send({@Body() required Email body}) async {
    await emailHandler.send(body);
  }
}
