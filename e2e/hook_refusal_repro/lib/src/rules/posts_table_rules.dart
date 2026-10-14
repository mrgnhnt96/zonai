import 'package:zonai_hook_refusal_repro/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostTableRules main() => PostTableRules();

/// Open, so every refusal the test sees comes from the hooks.
final class PostTableRules extends TableRules<PostTable, Post> {
  PostTableRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;
}
