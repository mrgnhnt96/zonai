import 'package:zonai/zonai.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai_schema/zonai_schema.dart';

class AuthHandler {
  const AuthHandler();

  Future<Map<String, Object?>?> adminAuthenticate(AdminAuthBody body) async {
    if (body case final AuthBody body) {
      return authenticate(body);
    }

    throw ArgumentError(
      'Unexpected body type, needs to be a $AuthBody, got ${body.runtimeType}',
    );
  }

  Future<Map<String, Object?>?> authenticate(AuthBody body) async {
    final payload = switch (body) {
      SignInAuthBody() => SignInPasswordAuthPayload(
        email: body.email,
        password: body.password,
      ),
      SignUpAuthBody() => SignUpPasswordAuthPayload(
        email: body.email,
        password: body.password,
        object: body.object,
      ),
      SendOtpAuthBody() => SendOtpAuthPayload(
        email: body.email,
        object: body.metadata,
      ),
      SendMagicLinkAuthBody() => SendMagicLinkAuthPayload(
        email: body.email,
        object: body.metadata,
      ),
    };

    final result = switch (body) {
      AdminAuthBody() => await zonaiDB.authenticateAdmin(payload),
      _ => await zonaiDB.authenticate(body.collection, payload),
    };

    return switch ((body, result)) {
      (SignInAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (SignUpAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (SendOtpAuthBody(), null) => null,
      (VerifyOtpAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (SendMagicLinkAuthBody(), null) => null,
      (VerifyMagicLinkAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      _ => throw UnimplementedError('Unknown auth body: $body'),
    };
  }

  Future<Map<String, Object?>?> verifyAuth(VerifyAuthBody body) async {
    final VerifyAuthPayload payload = switch (body) {
      VerifyOtpAuthBody() => VerifyOtpAuthPayload(
        email: body.email,
        code: body.code,
      ),
      VerifyMagicLinkAuthBody() => VerifyMagicLinkAuthPayload(
        secret: body.secret,
      ),
      ConfirmResetPasswordAuthBody() => ConfirmResetPasswordAuthPayload(
        token: body.token,
        newPassword: body.newPassword,
      ),
    };

    final result = await zonaiDB.confirmAuth(payload);

    return switch ((body, result)) {
      (VerifyOtpAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (VerifyMagicLinkAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (ConfirmResetPasswordAuthBody(), null) => null,
      _ => throw UnimplementedError('Unknown verify auth body: $body'),
    };
  }

  Future<Map<String, Object?>> signIn(SignInAuthBody body) async {
    final result = await zonaiDB.authenticate(
      body.collection,
      SignInPasswordAuthPayload(email: body.email, password: body.password),
    );
    return _sessionPayload(result!.user, result.jwt);
  }

  Future<Map<String, Object?>> signUp(
    String? authorization,
    SignUpAuthBody body,
  ) async {
    final token = switch (authorization) {
      null => null,
      final String bearerToken => _parseBearerAuthorization(bearerToken),
    };
    final result = await zonaiDB.authenticate(
      body.collection,
      SignUpPasswordAuthPayload(
        email: body.email,
        password: body.password,
        object: body.object,
        jwt: token,
      ),
    );
    return _sessionPayload(result!.user, result.jwt);
  }

  Future<void> logout(String authorizationHeader) async {
    final token = _parseBearerAuthorization(authorizationHeader);
    await zonaiDB.logout(token);
  }

  Future<void> logoutAll(String authorizationHeader) async {
    final token = _parseBearerAuthorization(authorizationHeader);
    await zonaiDB.logoutAll(token);
  }

  Future<void> sendResetPassword({
    required ResetPasswordAuthBody body,
    String? authorization,
  }) async {
    final token = switch (authorization) {
      null => null,
      final String bearerToken => _parseBearerAuthorization(bearerToken),
    };
    final payload = ResetPasswordAuthPayload(email: body.email, jwt: token);

    switch (body) {
      case AdminSendResetPasswordAuthBody():
        await zonaiDB.sendAdminResetPassword(payload);
      case SendResetPasswordAuthBody():
        await zonaiDB.sendResetPassword(body.collection, payload);
    }
  }

  Map<String, Object?> _sessionPayload(
    Map<String, Object?> user,
    String accessToken,
  ) {
    return {'accessToken': accessToken, 'user': user};
  }

  String _parseBearerAuthorization(String authorizationHeader) {
    final trimmed = authorizationHeader.trim();
    if (trimmed.isEmpty) {
      throw StateError('Authorization header is required');
    }

    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      final token = trimmed.substring(prefix.length).trim();
      if (token.isEmpty) throw StateError('Bearer token is empty');
      return token;
    }

    return trimmed;
  }
}
