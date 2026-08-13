// Members of a table's operations file, where a custom operation is
// implemented -- `custom(...)` and the query it builds.
import 'package:my_app/src/schemas/posts.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/zonai_schema.dart';

final class PostOperations extends TableOperations<PostTable, Post> {
  PostOperations() : super(posts);

  // <<body>>
}
