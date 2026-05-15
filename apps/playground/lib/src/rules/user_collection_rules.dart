import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserCollectionRules main() => UserCollectionRules();

final class UserCollectionRules extends AuthCollectionRules<UserCollection, User> {
  UserCollectionRules() : super(users);
}
