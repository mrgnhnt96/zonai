part of auth_collection;

abstract class Auth implements SupportedAuths {
  const Auth();

  ColumnType<Id> get id;
}

mixin HasEmail on Auth {
  EmailColumn get email;
  IsVerifiedColumn get isVerified;
}

base mixin PasswordAuth on Auth implements HasEmail {
  PasswordColumn get passwordHash;

  @override
  @nonVirtual
  bool get supportsPassword => true;
}

base mixin OtpAuth on Auth implements HasEmail {
  @override
  @nonVirtual
  bool get supportsOtp => true;
}

base mixin MagicLinkAuth on Auth implements HasEmail {
  @override
  @nonVirtual
  bool get supportsMagicLink => true;
}
