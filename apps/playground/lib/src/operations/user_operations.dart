import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations {
  UserOperations() : super(users);

  @override
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims({'is_awesome': true});
  }
}

UserOperations main() => UserOperations();
