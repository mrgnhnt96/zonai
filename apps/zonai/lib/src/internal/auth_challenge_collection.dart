import 'package:zonai_schema/zonai_schema.dart';

class AuthChallenge {
  AuthChallenge({
    required this.id,
    required this.userId,
    required this.expiresAt,
    required this.metadata,
    required this.secretHash,
    required this.target,
    required this.collection,
    required this.type,
  }) : createdAt = DateTime.now(),
       canConsume = true,
       consumedAt = null;

  AuthChallenge._({
    required this.id,
    required this.userId,
    required this.expiresAt,
    required this.metadata,
    required this.secretHash,
    required this.target,
    required this.collection,
    required this.type,
    required this.createdAt,
    required this.consumedAt,
    required this.canConsume,
  });

  AuthChallenge.otp({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.collection,
    this.metadata,
  }) : userId = null,
       type = .otp,
       createdAt = DateTime.now(),
       canConsume = true,
       consumedAt = null;

  AuthChallenge.magicLink({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.collection,
    this.metadata,
  }) : userId = null,
       type = .magicLink,
       createdAt = DateTime.now(),
       canConsume = true,
       consumedAt = null;

  AuthChallenge.passwordReset({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.collection,
    this.metadata,
  }) : userId = null,
       type = .passwordReset,
       createdAt = DateTime.now(),
       canConsume = true,
       consumedAt = null;

  AuthChallenge.verifyEmail({
    required this.id,
    required this.expiresAt,
    required this.secretHash,
    required this.target,
    required this.collection,
    this.metadata,
  }) : userId = null,
       type = .verifyEmail,
       createdAt = DateTime.now(),
       canConsume = true,
       consumedAt = null;

  final AuthChallengeId id;
  final Id? userId;
  final DateTime expiresAt;
  final Map<String, Object?>? metadata;
  final String secretHash;
  final String target;
  final String collection;
  final AuthChallengeType type;
  final DateTime createdAt;
  final DateTime? consumedAt;
  final bool canConsume;
}

enum AuthChallengeType {
  otp,
  magicLink,
  verifyEmail,
  passwordReset,
  emailChange,
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

class AuthChallengeCollection extends Collection<AuthChallenge> {
  AuthChallengeCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: AuthChallengeId.new,
        generate: AuthChallengeId.generate,
      ),
      userId = $.id(
        'user_id',
        (s) => s.userId,
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
      collection = $.text('collection', (s) => s.collection),
      type = $.enumerator('type', AuthChallengeType.values, (s) => s.type),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      consumedAt = $.dateTime('consumed_at', (s) => s.consumedAt),
      canConsume = $.boolean('can_consume', (s) => s.canConsume);

  final IdColumn<AuthChallengeId> id;
  final IdColumn<UnknownId>? userId;
  final DateTimeColumn expiresAt;
  final MapColumn? metadata;
  final TextColumn secretHash;
  final TextColumn target;
  final TextColumn collection;
  final EnumColumn<AuthChallengeType> type;
  final DateTimeColumn createdAt;
  final DateTimeColumn? consumedAt;
  final BooleanColumn canConsume;

  @override
  AuthChallenge fromRow(RowReader read) {
    return AuthChallenge._(
      id: read(id),
      userId: read(userId),
      expiresAt: read(expiresAt),
      metadata: read(metadata),
      secretHash: read(secretHash),
      target: read(target)!,
      collection: read(collection),
      type: read(type),
      createdAt: read(createdAt),
      consumedAt: read(consumedAt),
      canConsume: read(canConsume),
    );
  }
}

final authChallenges = collection(
  '_auth_challenges',
  AuthChallengeCollection.new,
  (table) {
    index(
      'auth_challenges_target_collection_unique',
    ).on(table.target, table.collection);
    index('auth_challenges_consumed_unique').on(table.canConsume);
  },
);
