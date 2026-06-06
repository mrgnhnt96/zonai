import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../components/black_list.dart';
import '../components/body_rate_limit.dart';

@BlackList()
@Controller('auth')
class AuthController {
  const AuthController({required this.authHandler});

  final AuthHandler authHandler;

  @BodyRateLimit<AuthBody>(.authenticate)
  @Post()
  Future<Map<String, Object?>?> authenticate({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required AuthBody body,
  }) async {
    return await authHandler.authenticate(body, authorization: authorization);
  }

  @BodyRateLimit<AuthBody>(.refreshToken)
  @Post('refresh')
  Future<Map<String, Object?>?> refreshToken({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
  }) async {
    return await authHandler.refreshToken(authorization);
  }

  @BodyRateLimit<ResetPasswordAuthBody>(.sendResetPassword)
  @Post('reset-password')
  Future<void> sendResetPassword({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required ResetPasswordAuthBody body,
  }) async {
    await authHandler.sendResetPassword(
      authorization: authorization,
      body: body,
    );
  }

  @BodyRateLimit<VerifyEmailAuthBody>(.sendVerifyEmail)
  @Post('verify-email')
  Future<void> sendVerifyEmail({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
    @Body() VerifyEmailAuthBody? body,
  }) async {
    await authHandler.sendVerifyEmail(authorization: authorization, body: body);
  }

  @Post('confirm')
  Future<Map<String, Object?>?> confirm({
    @Body() required VerifyAuthBody body,
  }) async {
    return await authHandler.verifyAuth(body);
  }

  @Post('admin')
  Future<Map<String, Object?>?> adminAuthenticate({
    @Body() required AdminAuthBody body,
  }) async {
    return await authHandler.adminAuthenticate(body);
  }

  @BodyRateLimit<SignInAuthBody>(.signIn)
  @Post('sign-in')
  Future<Map<String, Object?>> signIn({
    @Body() required SignInAuthBody body,
  }) async {
    return await authHandler.signIn(body);
  }

  @BodyRateLimit<SignUpAuthBody>(.signUp)
  @Post('sign-up')
  Future<Map<String, Object?>> signUp({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required SignUpAuthBody body,
  }) async {
    return await authHandler.signUp(authorization, body);
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
