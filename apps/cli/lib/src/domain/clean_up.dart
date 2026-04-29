import 'dart:async';

import 'package:zonai/src/deps/logger.dart';

class CleanUp {
  factory CleanUp() => _instance ??= CleanUp._();
  CleanUp._() : _toClean = [];
  static CleanUp? _instance;

  final List<FutureOr<void> Function()> _toClean;

  void add(FutureOr<void> Function() toClean) {
    _toClean.add(toClean);
  }

  Future<void> run() async {
    logger.debug('Cleaning up');
    for (final toClean in _toClean) {
      try {
        switch (toClean) {
          case final Future<void> Function() fn:
            await fn();
          case final fn:
            fn();
        }
      } catch (e) {
        logger.error('Error cleaning up: $e');
      }
    }

    _toClean.clear();
    logger.debug('Cleaned up');
  }
}
