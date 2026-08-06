import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'authors.dart';

final class Post {
  Post({
    required this.id,
    required this.authorId,
    required this.title,
    required this.createdAt,
    this.body,
    this.updatedAt,
    this.photo,
  });

  final PostsId id;
  final AuthorsId authorId;
  final String title;
  final String? body;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final PhotoId? photo;
}

final class PostTable extends Table<Post> {
  PostTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PostsId.new,
        generate: PostsId.generate,
      ),
      photo = $.photo('photo', (s) => s.photo),
      authorId = $
          .id(
            'author_id',
            (s) => s.authorId,
            fromString: AuthorsId.new,
            generate: AuthorsId.generate,
            isPrimaryKey: false,
          )
          .references(() => authors.id, onDelete: ReferentialAction.cascade),
      title = $.text('title', (s) => s.title),
      body = $.text('body', (s) => s.body),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),

      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Post fromRow(RowReader read) {
    return Post(
      id: read(id),
      authorId: read(authorId),
      title: read(title),
      body: read(body),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
      photo: read(photo),
    );
  }

  final IdColumn<PostsId> id;
  final IdColumn<AuthorsId> authorId;
  final TextColumn title;
  final ColumnType<String?> body;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
  final ColumnType<PhotoId?> photo;
}

final posts = table('posts', PostTable.new);
