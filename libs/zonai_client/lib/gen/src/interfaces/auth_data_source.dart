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
  Future<void> logout({required String authorization});
  Future<void> logoutAll({required String authorization});
}
