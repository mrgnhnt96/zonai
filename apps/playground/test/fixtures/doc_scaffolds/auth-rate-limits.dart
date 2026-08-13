// Members of an auth table's rate-limit file -- `signInPolicy`, `signUpPolicy`
// and the other auth-specific overrides.
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserRateLimits extends AuthTableRateLimits<UserTable, User> {
  UserRateLimits() : super(users);

  // <<body>>
}
