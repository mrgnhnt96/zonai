import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/src/rate_limits/table/rate_limits.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

UserRateLimits main() => UserRateLimits();

final class UserRateLimits extends AuthTableRateLimits<UserTable, User> {
  UserRateLimits() : super(users);

  @override
  Future<RateLimitPolicy?> signInPolicy() async {
    return const RateLimitPolicy(
      maxRequests: 10,
      window: Duration(minutes: 15),
    );
  }

  @override
  Future<RateLimitPolicy?> signUpPolicy() async {
    return const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));
  }

  @override
  Future<RateLimitPolicy?> authenticatePolicy() async {
    return const RateLimitPolicy(
      maxRequests: 20,
      window: Duration(minutes: 15),
    );
  }

  @override
  Future<RateLimitPolicy?> sendResetPasswordPolicy() async {
    return const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));
  }

  @override
  Future<RateLimitPolicy?> sendVerifyEmailPolicy() async {
    return const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));
  }

  @override
  Future<RateLimitPolicy?> sendOtpPolicy() async {
    return const RateLimitPolicy(maxRequests: 5, window: Duration(minutes: 15));
  }

  @override
  Future<RateLimitPolicy?> sendMagicLinkPolicy() async {
    return const RateLimitPolicy(maxRequests: 5, window: Duration(minutes: 15));
  }
}
