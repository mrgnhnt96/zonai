import 'package:zonai_playground/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostRowRules main() => PostRowRules();

class PostRowRules extends RowRules<PostTable, Post> {
  PostRowRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt, Post row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Post row) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Post row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Post row) async => true;
}
