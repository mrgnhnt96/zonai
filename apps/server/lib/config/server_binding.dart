import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/settings.dart';

/// Default host and port when not overridden by CLI args.
abstract final class ServerBinding {
  static String get host {
    if (args.getOrNull<String>('host') case final value?) {
      return value;
    }

    if (settings.host case final value?) {
      return value;
    }

    return 'localhost';
  }

  static int get port {
    if (args.getOrNull<int>('port') case final value?) {
      return value;
    }

    if (settings.port case final value?) {
      return value;
    }

    return 8080;
  }
}
