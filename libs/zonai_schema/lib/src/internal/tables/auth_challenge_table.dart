import 'package:zonai_schema/zonai_schema.dart';

class AuthChallenge {
  AuthChallenge({
    required this.id,
    required this.userId,
    required this.expiresAt,
    required this.metadata,
    required this.secretHash,
    required this.target,
    required this.table,
    required this.type,
    required this.allowedAttempts,
  }) : createdAt = .now(),
       canConsume = true,
       consumedAt = null;

  AuthChallenge._({
    required this.id,
    required this.userId,
    required this.expiresAt,
    required this.metadata,
    required this.secretHash,
    required this.target,
    required this.table,
    required this.type,
    required this.createdAt,
    required this.consumedAt,
    required this.canConsume,
    required this.allowedAttempts,
  });

  AuthChallenge.otp({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.table,
    this.metadata,
  }) : userId = null,
       type = .otp,
       allowedAttempts = 3,
       createdAt = DateTime.now(),
       canConsume = true,
       consumedAt = null;

  AuthChallenge.magicLink({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.table,
    this.metadata,
  }) : userId = null,
       allowedAttempts = 1,
       type = .magicLink,
       createdAt = DateTime.now(),
       canConsume = true,
       consumedAt = null;

  AuthChallenge.passwordReset({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.table,
    this.metadata,
  }) : userId = null,
       allowedAttempts = 1,
       type = .passwordReset,
       createdAt = .now(),
       canConsume = true,
       consumedAt = null;

  AuthChallenge.verifyEmail({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.table,
    this.metadata,
  }) : userId = null,
       allowedAttempts = 1,
       type = .verifyEmail,
       createdAt = .now(),
       canConsume = true,
       consumedAt = null;

  /// `secretHash: sha256(state)`, `target`: provider id, `metadata`:
  /// `{verifier, nonce, redirectTo}`. Caller supplies a 10-minute
  /// [expiresAt] — see §4.1 of `docs/oauth-design.md`.
  AuthChallenge.oauthState({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.table,
    this.metadata,
  }) : userId = null,
       allowedAttempts = 1,
       type = .oauthState,
       createdAt = .now(),
       canConsume = true,
       consumedAt = null;

  final AuthChallengeId id;
  final Id? userId;
  final DateTime expiresAt;
  final Map<String, Object?>? metadata;
  final String secretHash;
  final String target;
  final String table;
  final AuthChallengeType type;
  final DateTime createdAt;
  final DateTime? consumedAt;
  final bool canConsume;
  final int allowedAttempts;
}

enum AuthChallengeType {
  otp,
  magicLink,
  verifyEmail,
  passwordReset,
  emailChange,

  /// OAuth's `state` + PKCE verifier (§4.1 of `docs/oauth-design.md`).
  /// `secretHash: sha256(state)`, `target`: provider id, `table`: auth
  /// collection, `metadata`: `{verifier, nonce, redirectTo}`,
  /// `allowedAttempts: 1`, 10-minute `expiresAt`.
  oauthState,
}

class AuthChallengeId implements Id {
  AuthChallengeId(this.value) {
    if (!value.endsWith(_suffix)) {
      throw ArgumentError.value(value, 'value', 'Value must end with $_suffix');
    }
  }
  static AuthChallengeId generate() => AuthChallengeId(Id.generate(_suffix));

  static const _suffix = 'ach';

  @override
  final String value;
}

class AuthChallengeTable extends Table<AuthChallenge> {
  AuthChallengeTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: AuthChallengeId.new,
        generate: AuthChallengeId.generate,
      ),
      userId = $.id<UnknownId, UnknownId?>(
        'user_id',
        (s) => s.userId == null ? null : UnknownId(s.userId!.value),
        fromString: UnknownId.new,
        generate: () => throw Exception(
          'User ID should not be generated for auth challenges',
        ),
        isPrimaryKey: false,
        synthetic: const UnknownId('__auth_challenge__'),
      ),
      expiresAt = $.dateTime('expires_at', (s) => s.expiresAt),
      metadata = $.map('metadata', (s) => s.metadata),
      secretHash = $.text('secret_hash', (s) => s.secretHash),
      target = $.text('target', (s) => s.target),
      table = $.text('table', (s) => s.table),
      type = $.enumerator('type', AuthChallengeType.values, (s) => s.type),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      consumedAt = $.dateTime('consumed_at', (s) => s.consumedAt),
      canConsume = $.boolean('can_consume', (s) => s.canConsume),
      allowedAttempts = $.integer('allowed_attempts', (s) => s.allowedAttempts);

  final IdColumn<AuthChallengeId> id;
  final ColumnType<UnknownId?> userId;
  final DateTimeColumn expiresAt;
  final ColumnType<Map<String, dynamic>?> metadata;
  final TextColumn secretHash;
  final TextColumn target;
  final TextColumn table;
  final EnumColumn<AuthChallengeType> type;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> consumedAt;
  final BooleanColumn canConsume;
  final IntColumn allowedAttempts;

  @override
  AuthChallenge fromRow(RowReader read) {
    return AuthChallenge._(
      id: read(id),
      userId: read(userId),
      expiresAt: read(expiresAt),
      metadata: read(metadata),
      secretHash: read(secretHash),
      target: read(target)!,
      table: read(table),
      type: read(type),
      createdAt: read(createdAt),
      consumedAt: read(consumedAt),
      canConsume: read(canConsume),
      allowedAttempts: read(allowedAttempts),
    );
  }
}

final authChallenges = table('_auth_challenges', AuthChallengeTable.new, (
  table,
) {
  index(
    'auth_challenges_target_collection_unique',
  ).on(table.target, table.table);
  index('auth_challenges_consumed_unique').on(table.canConsume);
});
