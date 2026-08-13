// Members of the extension for an auth table -- the `onSignUp`/`onSignIn`
// hooks the docs show without the class around them.
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserExtensions extends Extension<User> with AuthExtension<User> {
  UserExtensions() : super(users);

  // <<body>>
}
