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

  /// Bucket key used by `RateLimiter.checkExternalIdpProvisioning`.
  /// Policy is fixed at the framework level (no `AuthTableRateLimits`
  /// override surface); use the dedicated method, not `check`.
  externalIdpProvisioning,
}
