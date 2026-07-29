import 'package:zonai_stress_fixture/src/schemas/items.dart';
import 'package:zonai_schema/src/rate_limits/table/rate_limits.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

ItemRateLimits main() => ItemRateLimits();

/// Zonai defaults every operation to 100 req/min per (table, operation, IP)
/// -- see [RateLimitPolicy.defaultPolicy]. That's the right default for a
/// real app but it swamps a single-client load test almost immediately, so
/// this fixture disables limits (null = unlimited) to measure the server's
/// actual throughput ceiling instead of the rate limiter's.
final class ItemRateLimits extends TableRateLimits<ItemTable, Item> {
  ItemRateLimits() : super(items);

  @override
  Future<RateLimitPolicy?> getPolicy() async => null;

  @override
  Future<RateLimitPolicy?> limitPolicy() async => null;

  @override
  Future<RateLimitPolicy?> countPolicy() async => null;

  @override
  Future<RateLimitPolicy?> createPolicy() async => null;

  @override
  Future<RateLimitPolicy?> updatePolicy() async => null;

  @override
  Future<RateLimitPolicy?> deletePolicy() async => null;
}
