import 'package:zonai_playground/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostCollectionRules main() => PostCollectionRules();

final class PostCollectionRules extends CollectionRules<PostCollection, Post> {
  PostCollectionRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  Future<bool> canUpdate(Jwt? jwt) async => true;

  Future<bool> canDelete(Jwt? jwt) async => true;

  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
