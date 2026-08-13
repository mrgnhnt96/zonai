// Statements inside an extension hook -- the `get`/`mutate`/`email`/`logger`
// calls the docs show on their own when the subject is what a hook may *do*
// rather than which hook it is.
//
// The members below are the stand-ins the surrounding prose assumes ("the user
// who signed up", "the order that was placed"). They are getters that throw
// rather than locals: a local would have to be assigned to be readable, and
// assigning it would mean inventing a value, while the fragment only ever
// needs the *type*. Add one only when a doc's prose genuinely implies it -- a
// binding the reader cannot see is context they do not have, and a snippet
// that only compiles because of it is being checked against the wrong thing.
import 'package:my_app/src/schemas/comments.dart';
import 'package:my_app/src/schemas/posts.dart';
import 'package:my_app/src/schemas/purchases.dart';
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class SideEffectExample extends Extension<Post> {
  SideEffectExample() : super(posts);

  User get user => throw UnimplementedError();
  Purchase get purchase => throw UnimplementedError();
  Comment get comment => throw UnimplementedError();

  /// The pair an update hook is handed, for fragments about what changed.
  Post get before => throw UnimplementedError();
  Post get after => throw UnimplementedError();

  String get userId => throw UnimplementedError();
  String get sessionId => throw UnimplementedError();
  String get newCode => throw UnimplementedError();
  List<String> get recipientIds => throw UnimplementedError();

  @override
  Future<void> afterDeleteSuccess(Post post, Jwt? jwt) async {
    // <<body>>
  }
}
