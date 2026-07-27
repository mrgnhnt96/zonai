import 'package:raindrop/raindrop.dart' hide Table;
import 'package:zonai_schema/zonai_schema.dart';

import '../schemas/authors.dart';
import '../schemas/posts.dart';
import '../views/post_summary.dart';

ViewOperations<PostSummary> main() =>
    ViewOperations(postSummary, PostSummaryQuery());

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
