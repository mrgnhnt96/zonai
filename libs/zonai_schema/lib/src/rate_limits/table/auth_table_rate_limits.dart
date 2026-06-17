part of 'rate_limits.dart';

base class AuthTableRateLimits<S extends AuthTable<R>, R>
    implements RateLimits<S, R> {
  const AuthTableRateLimits(this.schema);

  @override
  final S schema;

  @override
  rd.Table<S, R> get table => rd.Table.getFor(schema);

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

  /// Throttles `onExternalAuthFirstSeen` hook invocations to bound the
  /// abuse vector where a hostile external IdP mints a flood of unique
  /// `sub` claims to provision unbounded rows in this auth table.
  ///
  /// Defaults to 60 attempts per hour per table (returned by the base
  /// `defaultPolicy`). Override to tighten or return `null` to disable.
  Future<RateLimitPolicy?> externalAuthFirstSeenPolicy() async =>
      const RateLimitPolicy(maxRequests: 60, window: Duration(hours: 1));
}
