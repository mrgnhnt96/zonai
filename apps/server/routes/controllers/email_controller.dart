// ! All `authorization` headers MUST have the same parameter name "authorization" so
// that we can properly inject the token into the request on the client side
import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/email_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../components/black_list.dart';

/// Sends mail.
///
/// `@BlackList()` is an IP ban check and nothing more -- it refuses addresses
/// already recorded as abusers and passes everyone else, so on its own it left
/// this route open to any caller who had not yet been caught. Authorisation,
/// throttling and recipient/template checks all live in [EmailHandler], which
/// is why the token and client IP are threaded through to it.
@BlackList()
@Controller('email')
class EmailController {
  const EmailController({required this.emailHandler});

  final EmailHandler emailHandler;

  @Post()
  Future<void> send({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Ip() required String ipAddress,
    @Body() required Email body,
  }) async {
    await emailHandler.send(
      body,
      authorization: authorization,
      ipAddress: ipAddress,
    );
  }
}
