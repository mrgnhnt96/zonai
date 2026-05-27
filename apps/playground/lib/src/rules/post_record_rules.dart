import 'package:zonai_playground/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostRecordRules main() => PostRecordRules();

class PostRecordRules extends RecordRules<PostTable, Post> {
  PostRecordRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt, Post record) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Post record) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Post record) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Post record) async => true;
}
