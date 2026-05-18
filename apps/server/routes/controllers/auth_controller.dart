import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

@Controller('auth')
class AuthController {
  const AuthController({required this.authHandler});

  final AuthHandler authHandler;

  @Post()
  Future<Map<String, Object?>> authenticate({
    @Body() required AuthBody body,
  }) async {
    return await authHandler.authenticate(body);
  }

  @Post('sign-in')
  Future<Map<String, Object?>> signIn({
    @Body() required SignInAuthBody body,
  }) async {
    return await authHandler.signIn(body);
  }

  @Post('sign-up')
  Future<Map<String, Object?>> signUp({
    @Body() required SignUpAuthBody body,
  }) async {
    return await authHandler.signUp(body);
  }

  @Delete()
  Future<void> logout({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
  }) async {
    await authHandler.logout(authorization);
  }

  @Delete('all')
  Future<void> logoutAll({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
  }) async {
    await authHandler.logoutAll(authorization);
  }
}
