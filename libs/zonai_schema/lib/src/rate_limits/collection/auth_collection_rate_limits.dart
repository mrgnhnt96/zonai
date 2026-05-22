part of 'rate_limits.dart';

base class AuthCollectionRateLimits<S extends AuthCollection<R>, R>
    implements RateLimits<S, R> {
  const AuthCollectionRateLimits(this.schema);

  @override
  final S schema;

  @override
  Table<S, R> get table => Table.getFor(schema);

  Future<RateLimitPolicy?> signInPolicy() async => null;

  Future<RateLimitPolicy?> signUpPolicy() async => null;

  Future<RateLimitPolicy?> authenticatePolicy() async => null;

  Future<RateLimitPolicy?> sendResetPasswordPolicy() async => null;

  Future<RateLimitPolicy?> sendVerifyEmailPolicy() async => null;

  Future<RateLimitPolicy?> confirmPolicy() async => null;

  Future<RateLimitPolicy?> sendOtpPolicy() async => null;

  Future<RateLimitPolicy?> sendMagicLinkPolicy() async => null;

  Future<RateLimitPolicy?> logoutPolicy() async => null;

  Future<RateLimitPolicy?> logoutAllPolicy() async => null;

  Future<RateLimitPolicy?> adminAuthenticatePolicy() async => null;

  Future<RateLimitPolicy?> adminSignInPolicy() async => null;
}
