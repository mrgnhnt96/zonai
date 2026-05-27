import 'package:zonai_playground/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostTableRules main() => PostTableRules();

final class PostTableRules extends TableRules<PostTable, Post> {
  PostTableRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  Future<bool> canUpdate(Jwt? jwt) async => true;

  Future<bool> canDelete(Jwt? jwt) async => true;

  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
