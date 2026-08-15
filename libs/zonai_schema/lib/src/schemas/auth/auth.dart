part of auth_table;

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

base mixin OAuth on Auth implements HasEmail {
  /// Providers this collection can sign in with. Must be non-empty and
  /// every [OAuthProvider.id] must be unique within the list — see
  /// [validateOAuthProviders].
  List<OAuthProvider> get oauthProviders;

  @override
  @nonVirtual
  bool get supportsOAuth => true;

  /// Throws a [StateError] if [oauthProviders] is empty or contains a
  /// duplicate [OAuthProvider.id]. Each provider validates its own
  /// credentials at construction; call this once at table-registration
  /// time so a misconfigured provider *list* fails at boot too, not on
  /// first sign-in.
  @nonVirtual
  void validateOAuthProviders() {
    if (oauthProviders.isEmpty) {
      throw StateError('$runtimeType.oauthProviders must not be empty');
    }

    final seen = <String>{};
    for (final provider in oauthProviders) {
      if (!seen.add(provider.id)) {
        throw StateError(
          '$runtimeType.oauthProviders has a duplicate id: "${provider.id}"',
        );
      }
    }
  }
}
