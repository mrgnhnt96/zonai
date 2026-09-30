import 'package:zonai_schema/zonai_schema.dart' as z;

final class UsersId implements z.Id {
  const UsersId(this.value);

  factory UsersId.generate() =>
      UsersId('${DateTime.now().microsecondsSinceEpoch}_usr');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}

/// Note ids are chosen by the CLIENT (offline creation), so any string is
/// accepted; `generate` is only the server's fallback.
final class NotesId implements z.Id {
  const NotesId(this.value);

  factory NotesId.generate() =>
      NotesId('${DateTime.now().microsecondsSinceEpoch}_note');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}
