import 'package:raindrop/raindrop.dart' show ReferentialAction;
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
  });

  final PostsId id;
  final AuthorsId authorId;
  final String title;
  final String? body;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class PostCollection extends Collection<Post> {
  PostCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PostsId.new,
        generate: PostsId.generate,
      ),
      authorId = $.id(
        'author_id',
        (s) => s.authorId,
        fromString: AuthorsId.new,
        generate: AuthorsId.generate,
        isPrimaryKey: false,
      ).references(() => authors.id, onDelete: ReferentialAction.cascade),
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
    );
  }

  final IdColumn<PostsId> id;
  final IdColumn<AuthorsId> authorId;
  final TextColumn title;
  final TextColumn? body;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;
}

final posts = collection('posts', PostCollection.new);
