import 'package:zonai_schema/zonai_schema.dart';

/// The credential that keeps an anonymous account reachable after its session
/// expires.
///
/// An anonymous account has no address and no password, so once its token
/// lapses nothing else could sign it back in. This row is that way back in:
/// `POST /auth/anonymous` returns a `zonai_anon_...` secret once, the device
/// keeps it, and `POST /auth/anonymous/resume` trades it for a fresh session.
/// It is accepted there and nowhere else -- never as a bearer.
///
/// Only [secretHash] is stored. The plaintext is 256 bits of CSPRNG output, so
/// SHA-256 is the right hash for the same reason it is for `_api_tokens`: there
/// is no dictionary to run against it.
///
/// Deleted when the account is upgraded (a verified account signs in through
/// its verified channel; a non-expiring credential for it would be a password
/// nobody chose) and when the account is deleted.
class AnonymousCredential {
  AnonymousCredential({
    required this.id,
    required this.table,
    required this.userId,
    required this.secretHash,
  }) : createdAt = .now(),
       lastUsedAt = null;

  AnonymousCredential._({
    required this.id,
    required this.table,
    required this.userId,
    required this.secretHash,
    required this.createdAt,
    required this.lastUsedAt,
  });

  final AnonymousCredentialId id;

  /// The auth collection's name, e.g. `'users'`.
  final String table;

  /// The anonymous row this credential resumes. A virtual reference, the same
  /// shape and the same gap as `_jwt.user_id` -- `table` names an app-defined
  /// schema, which this layer cannot express as a foreign key.
  final Id userId;

  /// `sha256(plaintext)`, hex. A secret column: stripped from every response
  /// and unfilterable through the public API, as `_api_tokens.token_hash` is.
  final String secretHash;

  final DateTime createdAt;

  /// Bumped on every resume; what an opt-in cleanup of abandoned anonymous
  /// accounts would key on.
  final DateTime? lastUsedAt;
}

class AnonymousCredentialId implements Id {
  AnonymousCredentialId(this.value) {
    if (!value.endsWith(_suffix)) {
      throw ArgumentError.value(value, 'value', 'Value must end with $_suffix');
    }
  }

  static AnonymousCredentialId generate() =>
      AnonymousCredentialId(Id.generate(_suffix));

  static const _suffix = 'anc';

  @override
  final String value;
}

class AnonymousCredentialTable extends Table<AnonymousCredential> {
  AnonymousCredentialTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: AnonymousCredentialId.new,
        generate: AnonymousCredentialId.generate,
      ),
      table = $.text('table', (s) => s.table),
      userId = $.id<UnknownId, UnknownId>(
        'user_id',
        (s) => UnknownId(s.userId.value),
        fromString: UnknownId.new,
        generate: () => throw Exception(
          'User ID should not be generated for anonymous credentials',
        ),
        isPrimaryKey: false,
        synthetic: const UnknownId('__anonymous_credential__'),
      ),
      secretHash = $.secret('secret_hash', (s) => s.secretHash),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      lastUsedAt = $.dateTime('last_used_at', (s) => s.lastUsedAt);

  final IdColumn<AnonymousCredentialId> id;
  final TextColumn table;
  final IdColumn<UnknownId> userId;
  final TextColumn secretHash;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> lastUsedAt;

  @override
  AnonymousCredential fromRow(RowReader read) {
    return AnonymousCredential._(
      id: read(id),
      table: read(table),
      userId: read(userId),
      secretHash: read(secretHash),
      createdAt: read(createdAt),
      lastUsedAt: read(lastUsedAt),
    );
  }
}

// The hash index is the resume lookup, and unique because two rows with one
// hash would mean one secret resumes two accounts. The (table, user_id) index
// makes "delete this account's credential" on upgrade and deletion one keyed
// write.
final anonymousCredentials = table(
  '_anonymous_credentials',
  AnonymousCredentialTable.new,
  (table) {
    uniqueIndex('anonymous_credential_hash_unique').on(table.secretHash);
    index('anonymous_credential_account').on(table.table, table.userId);
  },
);
