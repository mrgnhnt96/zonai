import 'package:zonai_schema/zonai_schema.dart';

class JwtId implements Id {
  const JwtId(this.value);
  static JwtId generate() => JwtId(Id.generate('jwt'));

  @override
  final String value;
}

class JwtCollection extends Collection<JwtCollection> {
  JwtCollection({required JwtId? id, required Id? userId})
    : id = $.id(
        'id',
        (s) => s.id,
        id,
        fromString: JwtId.new,
        generate: JwtId.generate,
      ),
      userId = $.id(
        'user_id',
        (s) => s.userId,
        userId,
        fromString: UnknownId.new,
        generate: () =>
            throw Exception('User ID is required for JWT collection'),
        isPrimaryKey: false,
      );

  final IdColumn<JwtId> id;
  final IdColumn<UnknownId> userId;

  static const $ = SchemaBuilder<JwtCollection>();
}

final jwts = collection(
  '_jwt',
  () => JwtCollection(id: JwtId.generate(), userId: const UnknownId('')),
);
