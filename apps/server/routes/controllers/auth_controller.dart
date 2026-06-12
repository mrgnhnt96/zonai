// ! All `authorization` headers MUST have the same parameter name "authorization" so
// that we can properly inject the token into the request on the client side
import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../components/black_list.dart';
import '../components/body_rate_limit.dart';

// TODO: Tighten up the return types so that we don't need to dynamically access
// the `accessToken` key

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
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.authenticate(
      body,
      authorization: authorization,
    );
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  @BodyRateLimit<AuthBody>(.refreshToken)
  @Post('refresh')
  Future<Map<String, Object?>?> refreshToken({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.refreshToken(authorization);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
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
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.verifyAuth(body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  @Post('admin')
  Future<Map<String, Object?>?> adminAuthenticate({
    @Body() required AdminAuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.adminAuthenticate(body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  @BodyRateLimit<SignInAuthBody>(.signIn)
  @Post('sign-in')
  Future<Map<String, Object?>> signIn({
    @Body() required SignInAuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.signIn(body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  @BodyRateLimit<SignUpAuthBody>(.signUp)
  @Post('sign-up')
  Future<Map<String, Object?>> signUp({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required SignUpAuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.signUp(authorization, body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
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
