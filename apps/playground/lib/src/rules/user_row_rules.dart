import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserRowRules main() => UserRowRules();

class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);

  // DELIBERATE, AND NOT A PATTERN TO COPY.
  //
  // `UserTable` carries `AsAdmin`, and `AsAdmin` grants `isAdmin` to every
  // row the table authenticates -- so this override makes anyone who hits
  // `POST /auth/sign-up` an admin of this playground. `AuthRowRules.canSignUp`
  // now denies exactly this combination by default; the playground opts back
  // in because its whole job is to have an admin JWT one request away.
  //
  // A real app wants one of two shapes instead: a separate `AsAdmin` table
  // with sign-up left closed (admins created by `zonai db admin create`), or
  // this table without `AsAdmin`.
  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
}
