part of auth_collection;

sealed class SupportedAuths {
  const SupportedAuths();

  List<AuthType> get authTypes {
    return [if (this is PasswordAuth) .password];
  }
}

enum AuthType { password }

base mixin PasswordAuth on Auth implements SupportedAuths {
  EmailColumn get email;
  PasswordColumn get passwordHash;
}
