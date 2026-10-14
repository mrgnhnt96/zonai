import 'package:zonai_hook_refusal_repro/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Post {
  Post({
    required this.id,
    required this.title,
    required this.createdAt,
    this.updatedAt,
  });

  final PostsId id;
  final String title;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class PostTable extends Table<Post> {
  PostTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PostsId.new,
        generate: PostsId.generate,
      ),
      title = $.text('title', (s) => s.title),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Post fromRow(RowReader read) {
    return Post(
      id: read(id),
      title: read(title),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<PostsId> id;
  final TextColumn title;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final posts = table('posts', PostTable.new);
