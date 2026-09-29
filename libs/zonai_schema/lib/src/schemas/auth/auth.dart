part of auth_table;

abstract class Auth implements SupportedAuths {
  const Auth();

  ColumnType<Id> get id;
}

mixin HasEmail on Auth {
  /// Non-null for every table except an [AnonymousAuth] one, whose rows carry
  /// no address until they are upgraded. Declaring it as an [EmailColumn]
  /// still satisfies this getter.
  ColumnType<String?> get email;
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

/// Lets a table hold accounts that exist before their owner gives an address.
///
/// An anonymous row is an ordinary row of this table whose email is NULL. It
/// is created by `POST /auth/anonymous`, kept alive past the token lifetime by
/// a device-held credential, and upgraded in place -- same primary key -- once
/// its owner proves a mailbox. Every email lookup is an equality on the email
/// column, and NULL never equals anything, so the OTP, magic-link, password
/// and reset flows cannot reach an anonymous row at all.
///
/// Requires the email column to be nullable ([NullableEmailColumn]), and may
/// not be combined with `AsAdmin`: admin is a property of the table, so every
/// anonymous visitor would be an admin. Both are checked when the operations
/// worker registers its tables, so a misdeclared table fails at boot.
base mixin AnonymousAuth on Auth implements HasEmail {
  @override
  @nonVirtual
  bool get supportsAnonymous => true;
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
