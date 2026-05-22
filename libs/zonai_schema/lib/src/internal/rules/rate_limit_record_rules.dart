import 'package:zonai_schema/src/internal/rate_limit_collection.dart';
import 'package:zonai_schema/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

RateLimitRecordRules main() => RateLimitRecordRules();

final class RateLimitRecordRules
    extends InternalRecordRules<RateLimitCollection, RateLimitEntry> {
  RateLimitRecordRules() : super(rateLimits);

  @override
  Future<bool> canDelete(Jwt? jwt, RateLimitEntry record) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
