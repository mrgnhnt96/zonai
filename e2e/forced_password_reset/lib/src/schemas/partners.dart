import 'package:zonai_forced_password_reset/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Partner {
  Partner({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.createdAt,
    this.updatedAt,
  });

  final PartnersId id;
  final String email;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

/// Passwordless: `OtpAuth` and `OAuth`, deliberately NO `PasswordAuth`.
///
/// There is no password column here, so there is no password sign-in for a
/// requirement to gate.
/// `requirePasswordReset` must refuse rather than write a row that is
/// unenforceable by construction -- an operator who "forced a reset" on this
/// table and got a success would reasonably believe the account was
/// constrained.
///
/// `OtpAuth` is what lets an account exist here at all: `db.create` refuses
/// an auth table outright ("Cannot create auth records, use the auth API
/// instead"), and the OAuth door needs a real provider round trip. An OTP
/// sign-up creates the row through the auth API with no password, which is
/// exactly the state the refusal is about.
///
/// The provider list only has to be non-empty and well-formed
/// (`validateOAuthProviders`); nothing in this fixture ever contacts it.
final class PartnerTable extends AuthTable<Partner> with OtpAuth, OAuth {
  PartnerTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PartnersId.new,
        generate: PartnersId.generate,
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Partner fromRow(RowReader read) {
    return Partner(
      id: read(id),
      email: read(email),
      isVerified: read(isVerified),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<PartnersId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;

  @override
  List<OAuthProvider> get oauthProviders => [
    OAuthProvider.custom(
      id: 'never-called',
      displayName: 'Never Called',
      endpoints: const OAuthEndpoints(
        authorization: 'http://127.0.0.1:1/authorize',
        token: 'http://127.0.0.1:1/token',
        userInfo: 'http://127.0.0.1:1/userinfo',
      ),
      scopes: const ['openid', 'email'],
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
      ),
      clientId: 'never-called-client-id',
      clientSecret: 'never-called-client-secret',
      usesPkce: true,
    ),
  ];
}

final partners = authTable('partners', PartnerTable.new);
