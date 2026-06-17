import 'package:zonai_schema/src/internal/tables/rate_limit_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
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
