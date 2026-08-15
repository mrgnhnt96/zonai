enum RateLimitOperation {
  get,
  list,
  count,
  create,
  update,
  delete,
  signIn,
  signUp,
  authenticate,
  refreshToken,
  sendResetPassword,
  sendVerifyEmail,
  confirm,
  sendOtp,
  sendMagicLink,
  logout,
  logoutAll,
  adminAuthenticate,
  adminSignIn,

  /// Named custom operations (`TableOperations.custom`). The specific
  /// operation name travels separately — see [RateLimitRequest.customOperation].
  custom,

  /// Bucket key used by `RateLimiter.checkExternalIdpProvisioning`.
  /// Policy is fixed at the framework level (no `AuthTableRateLimits`
  /// override surface); use the dedicated method, not `check`.
  externalIdpProvisioning,

  /// `GET /auth/oauth/start/:provider?table=` (design §3.1 step 1, §4 item 8).
  /// Bucketed per auth table, like every other auth operation, because the
  /// caller names the table it is starting a flow for. Override with
  /// `AuthTableRateLimits.oauthStartPolicy`.
  oauthStart,

  /// `GET`/`POST /auth/oauth/callback/:provider` (design §3.1 step 2,
  /// §4 item 8).
  ///
  /// Unlike every other auth operation this one has **no table to bucket
  /// by**: the callback carries only `state`, and the table is resolved from
  /// the `oauthState` challenge that `state` hashes to — inside the db
  /// mutator, long after a guard has run. So the bucket key is a single
  /// constant per client IP and the policy is fixed at the framework level
  /// (no `AuthTableRateLimits` override surface), the same shape
  /// [externalIdpProvisioning] uses. Take it through
  /// `RateLimit.checkOAuthCallback`, never `check`.
  ///
  /// Do **not** be tempted to bucket this by the `:provider` path segment
  /// instead. That segment is caller-supplied and unvalidated at guard time,
  /// so rotating it (`/callback/a`, `/callback/b`, …) would hand every
  /// request a fresh counter — the identical bypass
  /// `RateLimit.checkCustomOperation` exists to close for `:operation`.
  oauthCallback,
}
