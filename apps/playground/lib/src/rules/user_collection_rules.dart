import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart' hide User;

UserCollectionRules main() => UserCollectionRules();

final class UserCollectionRules extends AuthCollectionRules<User> {
  UserCollectionRules() : super(users);
}
