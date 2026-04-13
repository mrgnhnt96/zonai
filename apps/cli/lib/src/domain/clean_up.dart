import 'package:zonai_cli/src/deps/logger.dart';

class CleanUp {
  CleanUp() : _toClean = [];

  final List<void Function()> _toClean;

  void add(void Function() toClean) {
    _toClean.add(toClean);
  }

  void run() {
    for (final toClean in _toClean) {
      try {
        toClean();
      } catch (e) {
        logger.error('Error cleaning up: $e');
      }
    }

    _toClean.clear();
  }
}
