abstract interface class SupportedAuths {
  const SupportedAuths();

  bool get supportsPassword;
  bool get supportsOtp;
  bool get supportsMagicLink;
  bool get supportsOAuth;
  bool get supportsAnonymous;
}

enum AuthType { password, otp, magicLink, oauth, anonymous }
