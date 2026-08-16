import 'package:zonai_playground/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostTableRules main() => PostTableRules();

/// Table rules gate the OPERATION on the collection; the ownership decision
/// lives in [PostRowRules], which is the only layer that can see a row's
/// `author_id`. Reads are open because posts are public content; writes need
/// a caller who at least exists.
final class PostTableRules extends TableRules<PostTable, Post> {
  PostTableRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt != null;
}
