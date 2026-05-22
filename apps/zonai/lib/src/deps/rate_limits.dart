import 'package:scoped_deps/scoped_deps.dart';
import '../domain/rate_limit/rate_limits.dart';

RateLimitsCompiler? _rateLimits;

final rateLimitsProvider = create<RateLimitsCompiler>(
  () => _rateLimits ??= RateLimitsCompiler(),
);

RateLimitsCompiler get rateLimitsCompiler => read(rateLimitsProvider);
