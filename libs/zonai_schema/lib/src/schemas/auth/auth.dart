part of auth_collection;

abstract class Auth {
  const Auth();

  ColumnType<Id> get id;
}

base mixin PasswordAuth on Auth implements SupportedAuths {
  EmailColumn get email;
  PasswordColumn get passwordHash;

  @override
  @nonVirtual
  bool get supportsPassword => true;
}
