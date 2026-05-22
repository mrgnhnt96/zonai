import 'package:revali_router/revali_router.dart';

final class Exceptions implements LifecycleComponent {
  const Exceptions();

  ExceptionCatcherResult<Exception> handle(Exception exception) {
    print('Exception: $exception');

    return .handled();
  }
}
