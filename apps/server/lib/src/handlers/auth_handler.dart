import 'package:zonai/zonai.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai_schema/zonai_schema.dart';

class AuthHandler {
  const AuthHandler();

  Future<Map<String, Object?>> authenticate(AuthBody body) async {
    final result = await zonaiDB.authenticate(body.collection, switch (body) {
      SignInAuthBody() => SignInPasswordAuthPayload(
        email: body.email,
        password: body.password,
      ),
      SignUpAuthBody() => SignUpPasswordAuthPayload(
        email: body.email,
        password: body.password,
        object: body.object,
      ),
    });

    return _sessionPayload(result.user, result.jwt);
  }

  Future<Map<String, Object?>> signIn(SignInAuthBody body) async {
    final result = await zonaiDB.signIn(
      body.collection,
      SignInPasswordAuthPayload(email: body.email, password: body.password),
    );
    return _sessionPayload(result.user, result.jwt);
  }

  Future<Map<String, Object?>> signUp(SignUpAuthBody body) async {
    final result = await zonaiDB.signUp(
      body.collection,
      SignUpPasswordAuthPayload(
        email: body.email,
        password: body.password,
        object: body.object,
      ),
    );
    return _sessionPayload(result.user, result.jwt);
  }

  Future<void> logout(String authorizationHeader) async {
    final token = _parseBearerAuthorization(authorizationHeader);
    await zonaiDB.logout(token);
  }

  Future<void> logoutAll(String authorizationHeader) async {
    final token = _parseBearerAuthorization(authorizationHeader);
    await zonaiDB.logoutAll(token);
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
