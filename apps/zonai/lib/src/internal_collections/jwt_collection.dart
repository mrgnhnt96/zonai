import 'package:zonai_schema/zonai_schema.dart';

class JwtId implements Id {
  const JwtId(this.value);
  static JwtId generate() => JwtId(Id.generate('jwt'));

  @override
  final String value;
}

class JwtEntry {
  JwtEntry({required this.id, required this.userId});

  final JwtId id;
  final Id userId;
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
      );

  final IdColumn<JwtId> id;
  final IdColumn<UnknownId> userId;

  @override
  JwtEntry fromRow(RowReader read) {
    return JwtEntry(id: read(id), userId: read(userId));
  }
}

final jwts = collection('_jwt', JwtCollection.new, (table) {
  uniqueIndex('jwt_id_unique').on(table.id);
});
