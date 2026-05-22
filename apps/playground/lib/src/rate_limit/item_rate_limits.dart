import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/src/rate_limits/collection/rate_limits.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

ItemRateLimits main() => ItemRateLimits();

final class ItemRateLimits extends CollectionRateLimits<ItemCollection, Item> {
  ItemRateLimits() : super(items);

  @override
  Future<RateLimitPolicy?> getPolicy() async {
    return const RateLimitPolicy(
      maxRequests: 100,
      window: Duration(minutes: 1),
    );
  }

  @override
  Future<RateLimitPolicy?> limitPolicy() async {
    return const RateLimitPolicy(
      maxRequests: 100,
      window: Duration(minutes: 1),
    );
  }

  @override
  Future<RateLimitPolicy?> countPolicy() async {
    return const RateLimitPolicy(
      maxRequests: 100,
      window: Duration(minutes: 1),
    );
  }
}
