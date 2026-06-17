import 'package:zonai_schema/zonai_schema.dart';

class JwtEntry {
  JwtEntry({required this.id, required this.userId, required this.expiresAt});

  final JwtId id;
  final Id userId;
  final DateTime expiresAt;
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
        defaultValue: '0',
      );

  final IdColumn<JwtId> id;
  final IdColumn<UnknownId> userId;
  final DateTimeColumn expiresAt;

  @override
  JwtEntry fromRow(RowReader read) {
    return JwtEntry(
      id: read(id),
      userId: read(userId),
      expiresAt: read(expiresAt),
    );
  }
}

final jwts = table('_jwt', JwtTable.new, (table) {
  uniqueIndex('jwt_id_unique').on(table.id);
});
