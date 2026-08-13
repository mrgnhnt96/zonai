// Stand-in for the `comments` table the docs invent for their cascade and
// side-effect examples. See tasks.dart for why these fixtures exist and when
// to extend them.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Comment {
  const Comment({required this.id, required this.postId, required this.body});

  final CommentsId id;

  /// The post this comment hangs off, as an ID rather than a `String` -- the
  /// examples read `comment.postId.value`.
  final PostsId postId;
  final String body;
}

final class CommentTable extends Table<Comment> {
  CommentTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: CommentsId.new,
        generate: CommentsId.generate,
      ),
      postId = $.id(
        'post_id',
        (s) => s.postId,
        fromString: PostsId.new,
        generate: PostsId.generate,
        isPrimaryKey: false,
      ),
      body = $.text('body', (s) => s.body);

  @override
  Comment fromRow(RowReader read) =>
      Comment(id: read(id), postId: read(postId), body: read(body));

  final IdColumn<CommentsId> id;
  final IdColumn<PostsId> postId;
  final TextColumn body;
}

final comments = table('comments', CommentTable.new);
