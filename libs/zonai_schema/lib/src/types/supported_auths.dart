abstract interface class SupportedAuths {
  const SupportedAuths();

  bool get supportsPassword;
  bool get supportsOtp;
}

enum AuthType { password, otp }
