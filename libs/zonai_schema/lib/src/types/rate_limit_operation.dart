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
}
