import 'package:zonai_schema/src/internal/rate_limit_collection.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';

final class RateLimitOperations
    extends CollectionOperations<RateLimitCollection, RateLimitEntry> {
  RateLimitOperations() : super(rateLimits);
}

RateLimitOperations main() => RateLimitOperations();
