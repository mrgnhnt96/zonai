part of auth_collection;

sealed class AuthType {
  const AuthType();
}

base mixin PasswordAuth on Auth implements AuthType {
  TextColumn get email;
  PasswordColumn get passwordHash;
}
