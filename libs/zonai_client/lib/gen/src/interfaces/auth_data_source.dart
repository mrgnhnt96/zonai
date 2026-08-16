part of '../../interfaces.dart';

abstract interface class AuthDataSource {
  const AuthDataSource();

  Future<Map<String, Object?>?> authenticate({
    required AuthBody body,
    String? authorization,
  });
  Future<Map<String, Object?>?> refreshToken({required String authorization});
  Future<void> sendResetPassword({
    required ResetPasswordAuthBody body,
    String? authorization,
  });
  Future<void> sendVerifyEmail({
    VerifyEmailAuthBody? body,
    required String authorization,
  });
  Future<Map<String, Object?>?> confirm({required VerifyAuthBody body});
  Future<Map<String, Object?>?> adminAuthenticate({
    required AdminAuthBody body,
  });
  Future<Map<String, Object?>> signIn({required SignInAuthBody body});
  Future<Map<String, Object?>> signUp({
    required SignUpAuthBody body,
    String? authorization,
  });
  Future<void> oauthCallbackFormPost({
    required String provider,
    required OAuthCallbackBody body,
  });
  Future<Map<String, Object?>> oauth({required OAuthBody body});
  Future<List<Map<String, Object?>>> oauthProviders({String? table});
  Future<void> startOAuth({
    required String provider,
    required String table,
    String? redirectTo,
    String? authorization,
  });
  Future<void> startAdminOAuth({
    required String provider,
    String? redirectTo,
    String? authorization,
  });
  Future<Map<String, Object?>> adminInviteStatus({required String token});
  Future<void> startAdminInviteOAuth({
    required String provider,
    required String token,
    String? redirectTo,
  });
  Future<void> oauthCallback({
    required String provider,
    String? code,
    String? state,
    String? error,
  });
  Future<void> logout({required String authorization});
  Future<void> logoutAll({required String authorization});
}
