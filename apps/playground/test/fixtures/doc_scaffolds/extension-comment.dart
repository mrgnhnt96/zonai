// Members of the extension over the `comments` table the docs invent.
import 'package:my_app/src/schemas/comments.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class CommentExtensions extends Extension<Comment> {
  CommentExtensions() : super(comments);

  // <<body>>
}
