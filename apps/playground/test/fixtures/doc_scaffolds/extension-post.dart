// Members of a plain (non-auth) table extension.
import 'package:my_app/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PostExtensions extends Extension<Post> {
  PostExtensions() : super(posts);

  // <<body>>
}
