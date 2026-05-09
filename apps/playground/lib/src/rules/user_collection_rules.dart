import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart' hide User;

UserCollectionRules main() => UserCollectionRules();

class UserCollectionRules extends CollectionRules<User> {
  UserCollectionRules() : super(users);
}
