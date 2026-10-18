import 'package:zonai_webhook_repro/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostTableRules main() => PostTableRules();

/// Open but for creates, which only an admin may make -- so a row a
/// webhook writes proves it wrote as the server, not as the anonymous
/// caller.
final class PostTableRules extends TableRules<PostTable, Post> {
  PostTableRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt?.admin.canEdit ?? false;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;
}
