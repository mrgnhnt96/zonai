import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_response.dart';

class RateLimitsMailman extends Mailman<RateLimitRequest, RateLimitResponse> {
  RateLimitsMailman()
    : super(
        debugName: debug,
        executablePath: settings.compiledRateLimitPath,
        fromJson: RateLimitResponse.fromJson,
      );

  static const debug = 'RATE_LIMITS';
}
