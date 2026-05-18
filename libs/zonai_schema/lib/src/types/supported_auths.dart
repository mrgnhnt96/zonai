abstract interface class SupportedAuths {
  const SupportedAuths();

  bool get supportsPassword;
}

enum AuthType { password }
