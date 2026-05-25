part of 'rate_limits.dart';

base class AuthCollectionRateLimits<S extends AuthCollection<R>, R>
    implements RateLimits<S, R> {
  const AuthCollectionRateLimits(this.schema);

  @override
  final S schema;

  @override
  Table<S, R> get table => Table.getFor(schema);

  Future<RateLimitPolicy?> signInPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> refreshTokenPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> signUpPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> authenticatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> sendResetPasswordPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> sendVerifyEmailPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> confirmPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> sendOtpPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> sendMagicLinkPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> logoutPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> logoutAllPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> adminAuthenticatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> adminSignInPolicy() async => .defaultPolicy;
}
