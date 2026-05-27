import 'package:zonai/src/internal/rate_limit_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

RateLimitTableRules main() => RateLimitTableRules();

final class RateLimitTableRules
    extends InternalTableRules<RateLimitTable, RateLimitEntry> {
  RateLimitTableRules() : super(rateLimits);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
