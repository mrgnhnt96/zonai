import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/services/rate_limiter.dart';

RateLimiter? _rateLimiter;

final rateLimiterProvider = create<RateLimiter>(
  () => _rateLimiter ??= RateLimiter(),
);

RateLimiter get rateLimiter => read(rateLimiterProvider);
