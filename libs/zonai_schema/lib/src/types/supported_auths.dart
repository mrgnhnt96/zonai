abstract interface class SupportedAuths {
  const SupportedAuths();

  bool get supportsPassword;
  bool get supportsOtp;
  bool get supportsMagicLink;
}

enum AuthType { password, otp, magicLink }
