import 'package:raindrop/raindrop.dart' hide Table, table;
import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../schemas/authors.dart';
import '../schemas/posts.dart';

ViewOperations<PostSummary> main() =>
    ViewOperations(postSummary, PostSummaryQuery());

/// A read-only projection of `posts` joined with `authors`.
///
/// Defined here rather than under `schemasPath` — colocated with the query
/// that produces it, and outside the one directory the migration generator
/// actually scans, so it can never be mistaken for a real table. See
/// `docs/views.md`.
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

/// The join that defines `post_summary`: every post's title next to its
/// author's name. Column names selected here must match [PostSummaryTable]'s
/// own declared columns (`id`, `title`, `author_name`).
final class PostSummaryQuery extends ViewQuery<PostSummary> {
  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> query() {
    return db
        .select(
          posts.id.aliasedAs('id'),
          posts.title.aliasedAs('title'),
          authors.name.aliasedAs('author_name'),
        )
        .from(posts)
        .join(authors, on: posts.authorId.equals(authors.id));
  }

  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> countQuery() {
    return db
        .select(count(posts.id))
        .from(posts)
        .join(authors, on: posts.authorId.equals(authors.id));
  }
}
