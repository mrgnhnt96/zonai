import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A read-only projection of `posts` joined with `authors`.
///
/// Lives outside `schemasPath` deliberately — a view has no backing SQL
/// table, so it must never be discovered by the migration generator. See
/// `PostSummaryQuery` (`lib/src/operations/post_summary_operations.dart`)
/// for the join, and `docs/views.md`.
final class PostSummary {
  const PostSummary({
    required this.id,
    required this.title,
    required this.authorName,
  });

  final PostsId id;
  final String title;
  final String authorName;
}

final class PostSummaryTable extends Table<PostSummary> {
  PostSummaryTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PostsId.new,
        generate: PostsId.generate,
      ),
      title = $.text('title', (s) => s.title),
      authorName = $.text('author_name', (s) => s.authorName);

  @override
  PostSummary fromRow(RowReader read) => PostSummary(
    id: read(id),
    title: read(title)!,
    authorName: read(authorName)!,
  );

  final IdColumn<PostsId> id;
  final TextColumn title;
  final TextColumn authorName;
}

final postSummary = table('post_summary', PostSummaryTable.new);
