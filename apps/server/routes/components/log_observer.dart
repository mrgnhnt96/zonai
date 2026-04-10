import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/utils/logger.dart';

class LogObserver implements Observer {
  const LogObserver({@Dep() required this.logger});

  final Logger logger;

  @override
  Future<void> see(Request request, Future<Response> response) async {
    final stopwatch = Stopwatch()..start();

    final result = await response;

    stopwatch.stop();
    final method = request.method;
    final path = request.uri;

    logger.log(
      '[${result.statusCode}] ${stopwatch.elapsedMilliseconds}ms: '
      '$method $path',
    );
  }
}
