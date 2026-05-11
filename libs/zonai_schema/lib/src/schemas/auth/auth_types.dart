part of auth_collection;

sealed class _AuthType {
  const _AuthType();

  AuthType get authType;
}

enum AuthType { password }

base mixin PasswordAuth on Auth implements _AuthType {
  TextColumn get email;
  PasswordColumn get passwordHash;
  AuthType get authType => .password;
}
