part of 'rate_limits.dart';

base class AuthTableRateLimits<S extends AuthTable<R>, R>
    implements RateLimits<S, R> {
  const AuthTableRateLimits(this.schema);

  @override
  final S schema;

  @override
  rd.TableMeta<S, R> get table => schema.$ as rd.TableMeta<S, R>;

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

  /// Throttles `onExternalAuthFirstSeen` hook invocations for this auth
  /// table, keyed per client IP. Bounds the abuse vector where a
  /// compromised external IdP mints unique `sub` claims to provision
  /// unbounded rows. Override to tighten or return `null` to disable.
  Future<RateLimitPolicy?> externalIdpProvisioningPolicy() async =>
      .externalIdpProvisioning;
}
