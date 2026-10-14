import 'package:zonai_hook_refusal_repro/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostsExtensions main() => PostsExtensions();

/// Hooks that refuse by title, so the refusals and the writes that go
/// through run in the same compiled worker.
final class PostsExtensions extends Extension<Post> {
  PostsExtensions() : super(posts);

  @override
  Future<void> beforeCreate(Post object, Jwt? jwt) async {
    switch (object.title) {
      case 'refuse':
        throw const HttpError.forbidden(
          code: 'post_refused',
          message: 'That title is not allowed',
          details: {'field': 'title'},
        );
      case 'refuse-500':
        throw const HttpError.internal(code: 'hook_5xx', message: 'Not 4xx');
      case 'crash':
        throw StateError('beforeCreate crashed');
    }
  }

  @override
  Future<void> beforeUpdate(Post row, Jwt? jwt) async {
    if (row.title == 'frozen') {
      throw const HttpError.conflict(
        code: 'post_frozen',
        message: 'A frozen post cannot change',
      );
    }
  }

  @override
  Future<void> beforeDelete(Post row, Jwt? jwt) async {
    if (row.title == 'pinned') {
      throw const HttpError.forbidden(
        code: 'post_pinned',
        message: 'A pinned post cannot be deleted',
      );
    }
  }
}
