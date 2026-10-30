import 'package:zonai_schema/zonai_schema.dart';

class JwtEntry {
  JwtEntry({
    required this.id,
    required this.userId,
    required this.expiresAt,
    this.anonymous = false,
    this.replaces,
  });

  final JwtId id;
  final Id userId;
  final DateTime expiresAt;

  /// Whether the session was issued to an anonymous account. Stored so the
  /// server re-derives `Jwt.isAnonymous` from here on every request, the same
  /// way it re-derives `admin` from the schema: a token claiming it is not
  /// anonymous proves nothing, even with a leaked signing key.
  final bool anonymous;

  /// The session this one was refreshed from, until this one is first used.
  ///
  /// A refresh keeps the old row instead of deleting it, because the reply
  /// carrying the new token can be lost (the app suspended mid-request, the
  /// signal dropped) and the old token is then all the client has. Deleting
  /// it at refresh signed those clients out. The first request -- or refresh
  /// -- made with this session deletes the row named here and clears it.
  final JwtId? replaces;
}

class JwtTable extends Table<JwtEntry> {
  JwtTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: JwtId.new,
        generate: JwtId.generate,
      ),
      userId = $.id<UnknownId, UnknownId>(
        'user_id',
        (s) => UnknownId(s.userId.value),
        fromString: UnknownId.new,
        generate: () => throw Exception('User ID is required for JWT table'),
        isPrimaryKey: false,
        synthetic: const UnknownId('__zonai_schema_registration__'),
        // TODO: It would be nice to add a `references` to the table here
      ),
      expiresAt = $.dateTime(
        'expires_at',
        (s) => s.expiresAt,
        // Epoch: the same instant the old raw-SQL default '0' meant, now
        // expressed as the DateTime the column actually stores.
        defaultValue: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      anonymous = $.boolean(
        'anonymous',
        (s) => s.anonymous,
        defaultValue: false,
      ),
      replaces = $.id<JwtId, JwtId?>(
        'replaces',
        (s) => s.replaces,
        fromString: JwtId.new,
        generate: () => throw Exception('A replaced JWT ID is never generated'),
        isPrimaryKey: false,
        synthetic: const JwtId('__zonai_schema_registration__'),
      );

  final IdColumn<JwtId> id;
  final IdColumn<UnknownId> userId;
  final DateTimeColumn expiresAt;
  final BooleanColumn anonymous;
  final ColumnType<JwtId?> replaces;

  @override
  JwtEntry fromRow(RowReader read) {
    return JwtEntry(
      id: read(id),
      userId: read(userId),
      expiresAt: read(expiresAt),
      anonymous: read(anonymous),
      replaces: read(replaces),
    );
  }
}

final jwts = table('_jwt', JwtTable.new, (table) {
  uniqueIndex('jwt_id_unique').on(table.id);
});
