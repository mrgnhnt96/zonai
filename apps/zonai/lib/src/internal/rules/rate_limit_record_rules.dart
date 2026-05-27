import 'package:zonai/src/internal/rate_limit_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

RateLimitRecordRules main() => RateLimitRecordRules();

final class RateLimitRecordRules
    extends InternalRecordRules<RateLimitTable, RateLimitEntry> {
  RateLimitRecordRules() : super(rateLimits);

  @override
  Future<bool> canDelete(Jwt? jwt, RateLimitEntry record) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
