import 'package:zonai_schema/zonai_schema.dart';

/// One `(table, provider, subject)` binding — "this provider's user is this
/// row in `table`". The lookup key an OAuth sign-in resolves against before
/// falling back to email-based linking or provisioning; see
/// `docs/oauth-design.md` §3.3.
class OAuthIdentity {
  OAuthIdentity({
    required this.id,
    required this.table,
    required this.userId,
    required this.provider,
    required this.subject,
    required this.email,
  }) : createdAt = .now(),
       lastLoginAt = .now();

  OAuthIdentity._({
    required this.id,
    required this.table,
    required this.userId,
    required this.provider,
    required this.subject,
    required this.email,
    required this.createdAt,
    required this.lastLoginAt,
  });

  final OAuthIdentityId id;

  /// The auth collection's name, e.g. `'users'`.
  final String table;

  /// The `table` row this identity signs in as. Not a database foreign key
  /// — `table` names an app-defined schema, so the reference is virtual.
  /// See the no-cascade note on [oauthIdentities] below.
  final Id userId;

  /// [OAuthProvider.id], e.g. `'google'`.
  final String provider;

  /// The provider's `sub` claim (or GitHub's numeric user id).
  final String subject;

  /// The provider's email claim at last sign-in. Nullable — not every
  /// provider/scope combination returns one.
  final String? email;

  final DateTime createdAt;
  final DateTime lastLoginAt;
}

class OAuthIdentityId implements Id {
  OAuthIdentityId(this.value) {
    if (!value.endsWith(_suffix)) {
      throw ArgumentError.value(value, 'value', 'Value must end with $_suffix');
    }
  }

  static OAuthIdentityId generate() => OAuthIdentityId(Id.generate(_suffix));

  static const _suffix = 'oid';

  @override
  final String value;
}

class OAuthIdentityTable extends Table<OAuthIdentity> {
  OAuthIdentityTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: OAuthIdentityId.new,
        generate: OAuthIdentityId.generate,
      ),
      table = $.text('table', (s) => s.table),
      userId = $.id<UnknownId, UnknownId>(
        'user_id',
        (s) => UnknownId(s.userId.value),
        fromString: UnknownId.new,
        generate: () => throw Exception(
          'User ID should not be generated for OAuth identities',
        ),
        isPrimaryKey: false,
        synthetic: const UnknownId('__oauth_identity__'),
      ),
      provider = $.text('provider', (s) => s.provider),
      subject = $.text('subject', (s) => s.subject),
      email = $.text('email', (s) => s.email),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      lastLoginAt = $.dateTime('last_login_at', (s) => s.lastLoginAt);

  final IdColumn<OAuthIdentityId> id;
  final TextColumn table;
  final IdColumn<UnknownId> userId;
  final TextColumn provider;
  final TextColumn subject;
  final ColumnType<String?> email;
  final DateTimeColumn createdAt;
  final DateTimeColumn lastLoginAt;

  @override
  OAuthIdentity fromRow(RowReader read) {
    return OAuthIdentity._(
      id: read(id),
      table: read(table),
      userId: read(userId),
      provider: read(provider),
      subject: read(subject),
      email: read(email),
      createdAt: read(createdAt),
      lastLoginAt: read(lastLoginAt),
    );
  }
}

// No cascade on user deletion: `user_id` names a row in an app-defined
// table chosen dynamically per collection (`table`), which this schema
// layer cannot express as a real SQL foreign key — `_jwt.user_id` has the
// identical shape and the identical gap (see the TODO on `JwtTable.userId`
// in jwt_table.dart). A deleted user therefore leaves an orphaned identity
// row, same as it already leaves orphaned JWTs today; this is a pre-existing
// limitation of the framework, not a regression introduced here. Sweeping
// orphans would need a way to enumerate deletions across every app-defined
// auth table, which does not exist yet — out of scope for this table.
final oauthIdentities = table('_oauth_identities', OAuthIdentityTable.new, (
  table,
) {
  uniqueIndex(
    'oauth_identities_lookup_unique',
  ).on(table.table, table.provider, table.subject);
});
