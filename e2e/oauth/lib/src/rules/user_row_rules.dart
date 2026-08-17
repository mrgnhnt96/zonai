import 'package:zonai_oauth_e2e/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserRowRules main() => UserRowRules();

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);

  /// See `UserTableRules.canList` -- opened for the same reason.
  @override
  Future<bool> canView(Jwt? jwt, User row) async => true;

  // `UserTable` is `AsAdmin`, so `AuthRowRules.canSignUp` denies anonymous
  // sign-up by default -- see the doc comment there. This fixture's admin
  // invite tests create their acting admin over `POST /auth/sign-up` before
  // there is any admin to authorise it, so they opt back in explicitly.
  //
  // Not a pattern to copy: it makes every registrant an admin. It is right
  // here only because the fixture's whole purpose is to have an admin JWT
  // one request away.
  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
}
