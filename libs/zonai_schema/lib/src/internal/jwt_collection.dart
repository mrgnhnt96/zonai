import 'package:zonai_schema/zonai_schema.dart';

class JwtId implements Id {
  const JwtId(this.value);
  static JwtId generate() => JwtId(Id.generate('jwt'));

  @override
  final String value;
}

class JwtEntry {
  JwtEntry({required this.id, required this.userId, required this.expiresAt});

  final JwtId id;
  final Id userId;
  final DateTime expiresAt;
}

class JwtCollection extends Collection<JwtEntry> {
  JwtCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: JwtId.new,
        generate: JwtId.generate,
      ),
      userId = $.id(
        'user_id',
        (s) => s.userId,
        fromString: UnknownId.new,
        generate: () =>
            throw Exception('User ID is required for JWT collection'),
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

final jwts = collection('_jwt', JwtCollection.new, (table) {
  uniqueIndex('jwt_id_unique').on(table.id);
});
