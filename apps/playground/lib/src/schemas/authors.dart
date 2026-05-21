import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Author {
  Author({
    required this.id,
    required this.name,
    required this.createdAt,
    this.updatedAt,
  });

  final AuthorsId id;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class AuthorCollection extends Collection<Author> {
  AuthorCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: AuthorsId.new,
        generate: AuthorsId.generate,
      ),
      name = $.text('name', (s) => s.name),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Author fromRow(RowReader read) {
    return Author(
      id: read(id),
      name: read(name),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<AuthorsId> id;
  final TextColumn name;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;
}

final authors = collection('authors', AuthorCollection.new);
