abstract interface class SupportedAuths {
  const SupportedAuths();

  bool get supportsPassword;
  bool get supportsOtp;
  bool get supportsMagicLink;
  bool get supportsOAuth;
}

enum AuthType { password, otp, magicLink, oauth }
