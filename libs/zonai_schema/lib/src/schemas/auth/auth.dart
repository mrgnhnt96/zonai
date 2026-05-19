part of auth_collection;

abstract class Auth {
  const Auth();

  ColumnType<Id> get id;
}

mixin HasEmail on Auth {
  EmailColumn get email;
}

base mixin PasswordAuth on Auth implements SupportedAuths, HasEmail {
  EmailColumn get email;
  PasswordColumn get passwordHash;

  @override
  @nonVirtual
  bool get supportsPassword => true;
}
