import 'package:zonai_schema/zonai_schema.dart';

class JwtEntry {
  JwtEntry({
    required this.id,
    required this.userId,
    required this.expiresAt,
    this.anonymous = false,
  });

  final JwtId id;
  final Id userId;
  final DateTime expiresAt;

  /// Whether the session was issued to an anonymous account. Stored so the
  /// server re-derives `Jwt.isAnonymous` from here on every request, the same
  /// way it re-derives `admin` from the schema: a token claiming it is not
  /// anonymous proves nothing, even with a leaked signing key.
  final bool anonymous;
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
      );

  final IdColumn<JwtId> id;
  final IdColumn<UnknownId> userId;
  final DateTimeColumn expiresAt;
  final BooleanColumn anonymous;

  @override
  JwtEntry fromRow(RowReader read) {
    return JwtEntry(
      id: read(id),
      userId: read(userId),
      expiresAt: read(expiresAt),
      anonymous: read(anonymous),
    );
  }
}

final jwts = table('_jwt', JwtTable.new, (table) {
  uniqueIndex('jwt_id_unique').on(table.id);
});
