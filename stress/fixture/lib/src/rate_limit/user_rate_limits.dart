import 'package:zonai_stress_fixture/src/schemas/users.dart';
import 'package:zonai_schema/src/rate_limits/table/rate_limits.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

UserRateLimits main() => UserRateLimits();

/// See item_rate_limits.dart -- disabled so the auth scenarios measure raw
/// sign-up/sign-in throughput instead of the platform's default auth limits
/// (10 sign-ins/15min, 5 sign-ups/hour), which would otherwise dominate.
final class UserRateLimits extends AuthTableRateLimits<UserTable, User> {
  UserRateLimits() : super(users);

  @override
  Future<RateLimitPolicy?> signInPolicy() async => null;

  @override
  Future<RateLimitPolicy?> signUpPolicy() async => null;

  @override
  Future<RateLimitPolicy?> authenticatePolicy() async => null;
}
