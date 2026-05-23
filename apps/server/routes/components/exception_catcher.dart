import 'package:revali_router/revali_router.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';

final class Exceptions implements LifecycleComponent {
  const Exceptions();

  ExceptionCatcherResult<Exception> handle(Exception exception) {
    if (exception case final ExecutableUnavailableException e) {
      return .handled(statusCode: 503, body: {'error': e.error});
    }

    if (kIsCompiled) {
      logger.error('Unhandled exception', exception);
      return .handled(statusCode: 500, body: {'error': '$exception'});
    }

    return const .handled();
  }
}
