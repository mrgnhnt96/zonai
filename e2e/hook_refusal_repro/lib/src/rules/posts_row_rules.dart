import 'package:zonai_hook_refusal_repro/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostRowRules main() => PostRowRules();

/// Open, like [PostTableRules].
final class PostRowRules extends RowRules<PostTable, Post> {
  PostRowRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt, Post row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Post row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Post before, Post after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Post row) async => true;
}
