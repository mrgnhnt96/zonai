import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserOperations extends CollectionOperations<User>
    with InsertReturning<User> {
  UserOperations() : super(users);
}

UserOperations main() => UserOperations();
