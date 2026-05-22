import 'package:zonai_schema/src/internal/rate_limit_collection.dart';
import 'package:zonai_schema/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

RateLimitCollectionRules main() => RateLimitCollectionRules();

final class RateLimitCollectionRules
    extends InternalCollectionRules<RateLimitCollection, RateLimitEntry> {
  RateLimitCollectionRules() : super(rateLimits);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
