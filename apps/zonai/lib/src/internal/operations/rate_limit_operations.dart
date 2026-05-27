import 'package:zonai/src/internal/tables/rate_limit_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class RateLimitOperations
    extends TableOperations<RateLimitTable, RateLimitEntry> {
  RateLimitOperations() : super(rateLimits);
}

RateLimitOperations main() => RateLimitOperations();
