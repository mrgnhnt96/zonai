import 'package:revali_router/revali_router.dart';
import '../../../../src/deps/logger.dart';

class LogObserver implements Observer {
  const LogObserver();

  @override
  Future<void> see(Request request, Future<Response> response) async {
    final stopwatch = Stopwatch()..start();

    final result = await response;

    stopwatch.stop();
    final method = request.method;
    final path = request.uri;

    logger.info(
      '[${result.statusCode}] ${stopwatch.elapsedMilliseconds}ms: '
      '$method $path',
    );
  }
}
