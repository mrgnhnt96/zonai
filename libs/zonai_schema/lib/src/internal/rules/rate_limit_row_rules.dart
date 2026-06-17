import 'package:zonai_schema/src/internal/tables/rate_limit_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

RateLimitRowRules main() => RateLimitRowRules();

final class RateLimitRowRules
    extends InternalRowRules<RateLimitTable, RateLimitEntry> {
  RateLimitRowRules() : super(rateLimits);

  @override
  Future<bool> canDelete(Jwt? jwt, RateLimitEntry row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
