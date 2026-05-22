part of 'rate_limits.dart';

base class AuthCollectionRateLimits<S extends AuthCollection<R>, R>
    implements RateLimits<S, R> {
  const AuthCollectionRateLimits(this.schema);

  @override
  final S schema;

  @override
  Table<S, R> get table => Table.getFor(schema);

  Future<RateLimitPolicy?> signInPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> signUpPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> authenticatePolicy() async =>
      RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> sendResetPasswordPolicy() async =>
      RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> sendVerifyEmailPolicy() async =>
      RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> confirmPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> sendOtpPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> sendMagicLinkPolicy() async =>
      RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> logoutPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> logoutAllPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> adminAuthenticatePolicy() async =>
      RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> adminSignInPolicy() async =>
      RateLimitPolicy.defaultPolicy;
}
