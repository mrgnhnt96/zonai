import 'package:zonai_playground/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PostOperations extends TableOperations<PostTable, Post> {
  PostOperations() : super(posts);
}

PostOperations main() => PostOperations();
