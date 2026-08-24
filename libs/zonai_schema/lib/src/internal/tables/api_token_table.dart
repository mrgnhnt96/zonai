import 'package:zonai_schema/zonai_schema.dart';

/// One API token: a credential issued out of band, valid until revoked, and
/// scoped to a named subset of the database.
///
/// The row is the whole authority. The string a caller sends is 256 bits of
/// CSPRNG output that exists nowhere on the server -- only [tokenHash] does --
/// so a token is exactly as powerful as [scope] says, for exactly as long as
/// the row says, and revoking it takes effect on the next request with no
/// restart and no redeploy.
class ApiTokenEntry {
  ApiTokenEntry({
    required this.id,
    required this.name,
    required this.tokenHash,
    required this.tokenPrefix,
    required this.scopeJson,
    required this.claims,
    required this.boundTable,
    required this.boundUserId,
    required this.expiresAt,
    required this.revokedAt,
    required this.createdAt,
    required this.createdBy,
    required this.lastUsedAt,
  });

  /// A freshly minted token. The caller has already generated the secret and
  /// hashed it; this class never sees the plaintext, which is the property
  /// that makes "shown once, at creation" true rather than aspirational.
  ApiTokenEntry.create({
    required this.name,
    required this.tokenHash,
    required this.tokenPrefix,
    required ApiTokenScope scope,
    required this.createdBy,
    this.claims = const {},
    this.boundTable,
    this.boundUserId,
    this.expiresAt,
  }) : id = ApiTokenId.generate(),
       scopeJson = scope.toJson(),
       revokedAt = null,
       createdAt = DateTime.now(),
       lastUsedAt = null;

  final ApiTokenId id;

  /// Human label -- "nightly-backup", "vercel-preview". Required, because a
  /// list of unnamed credentials is a list nobody ever revokes anything from.
  final String name;

  /// `sha256(plaintext)`, hex. A [SecretTransformer] column, so it is stripped
  /// from every response and cannot be filtered on through the public API.
  ///
  /// SHA-256 rather than Argon2 on purpose: the input is 256 bits of CSPRNG
  /// output, so there is no dictionary to run against it and the per-request
  /// cost of a memory-hard hash would buy nothing. That reasoning does not
  /// transfer to `$.password`, whose input a human chose.
  final String tokenHash;

  /// The first characters of the plaintext, kept so a human can match a token
  /// in a log line to a row without the server storing anything that opens it.
  final String tokenPrefix;

  final Map<String, dynamic> scopeJson;

  /// Merged into `jwt.claims`, so a rule already written against
  /// `jwt.claims['role']` works for an API token with no change.
  final Map<String, dynamic> claims;

  /// The auth collection this token acts as a row of, or null for a
  /// standalone service identity. See [ApiTokenJwt].
  final String? boundTable;
  final String? boundUserId;

  /// Null means **never**. That is the point of the feature, and it is why
  /// [revokedAt] has to exist: the only safe form of "forever" is "until
  /// someone says otherwise".
  final DateTime? expiresAt;

  /// Set rather than deleted, so revoking leaves an audit trail.
  final DateTime? revokedAt;

  final DateTime createdAt;

  /// The admin user id that minted it, or `__cli__`.
  final String createdBy;

  /// Written lazily (see `ZonaiDb`'s throttle) -- "used this hour" versus
  /// "not since March" is the whole decision this supports, so precision
  /// would cost a write per request and buy nothing.
  final DateTime? lastUsedAt;

  ApiTokenScope get scope => ApiTokenScope.fromJson(scopeJson);

  bool get isRevoked => revokedAt != null;

  bool isExpiredAt(DateTime now) => switch (expiresAt) {
    final expiresAt? => now.isAfter(expiresAt),
    null => false,
  };
}

class ApiTokenTable extends Table<ApiTokenEntry> {
  ApiTokenTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: ApiTokenId.new,
        generate: ApiTokenId.generate,
      ),
      name = $.text('name', (s) => s.name),
      tokenHash = $.secret('token_hash', (s) => s.tokenHash),
      tokenPrefix = $.text('token_prefix', (s) => s.tokenPrefix),
      scopeJson = $.map('scope', (s) => s.scopeJson),
      claims = $.map('claims', (s) => s.claims),
      boundTable = $.text('bound_table', (s) => s.boundTable),
      boundUserId = $.text('bound_user_id', (s) => s.boundUserId),
      expiresAt = $.dateTime('expires_at', (s) => s.expiresAt),
      revokedAt = $.dateTime('revoked_at', (s) => s.revokedAt),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      createdBy = $.text('created_by', (s) => s.createdBy),
      lastUsedAt = $.dateTime('last_used_at', (s) => s.lastUsedAt);

  final IdColumn<ApiTokenId> id;
  final TextColumn name;
  final TextColumn tokenHash;
  final TextColumn tokenPrefix;
  final MapColumn scopeJson;
  final MapColumn claims;
  final ColumnType<String?> boundTable;
  final ColumnType<String?> boundUserId;
  final ColumnType<DateTime?> expiresAt;
  final ColumnType<DateTime?> revokedAt;
  final DateTimeColumn createdAt;
  final TextColumn createdBy;
  final ColumnType<DateTime?> lastUsedAt;

  @override
  ApiTokenEntry fromRow(RowReader read) {
    return ApiTokenEntry(
      id: read(id),
      name: read(name),
      tokenHash: read(tokenHash),
      tokenPrefix: read(tokenPrefix),
      scopeJson: read(scopeJson),
      claims: read(claims),
      boundTable: read(boundTable),
      boundUserId: read(boundUserId),
      expiresAt: read(expiresAt),
      revokedAt: read(revokedAt),
      createdAt: read(createdAt),
      createdBy: read(createdBy),
      lastUsedAt: read(lastUsedAt),
    );
  }
}

final apiTokens = table('_api_tokens', ApiTokenTable.new, (table) {
  uniqueIndex('api_token_id_unique').on(table.id);
  // The only query on the hot path: resolve a presented credential. Without
  // it every authenticated API request is a full scan of this table.
  uniqueIndex('api_token_hash_unique').on(table.tokenHash);
});
