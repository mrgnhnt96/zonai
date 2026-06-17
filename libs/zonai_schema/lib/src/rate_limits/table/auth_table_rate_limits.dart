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

  /// Throttles `onExternalAuthFirstSeen` hook invocations for this auth
  /// table to bound the abuse vector where a compromised external IdP
  /// mints unique `sub` claims to provision unbounded rows.
  ///
  /// Each registered IdP gets its own bucket against this table, so a
  /// burst from one issuer does not exhaust the budget for others.
  ///
  /// Defaults to [externalAuthFirstSeenDefaultPolicy] (60 attempts per
  /// hour per bucket). Override to tighten or return `null` to disable.
  Future<RateLimitPolicy?> externalAuthFirstSeenPolicy() async =>
      externalAuthFirstSeenDefaultPolicy;
}

/// Default policy for `onExternalAuthFirstSeen` hook invocations: 60
/// attempts per hour per (auth-table, issuer) bucket.
///
/// Tighter than [RateLimitPolicy.defaultPolicy] because the first-seen
/// path provisions a new row in the auth table; the abuse cost per
/// request is higher than for an authenticated read.
const externalAuthFirstSeenDefaultPolicy = RateLimitPolicy(
  maxRequests: 60,
  window: Duration(hours: 1),
);
