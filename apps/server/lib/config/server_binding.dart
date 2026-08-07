import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/settings.dart';

/// Default host and port when not overridden by CLI args.
abstract final class ServerBinding {
  static String get host {
    final resolved = _resolvedHost();

    // 'localhost' is never passed to HttpServer.bind as-is: a hostname goes
    // through the platform resolver, which is free to hand back an AAAA
    // record first (macOS does), binding IPv6-loopback only and leaving IPv4
    // loopback and Android's 10.0.2.2 with no listener at all ("Connection
    // refused", not an obviously binding-family issue). The any-address
    // sidesteps resolver order entirely; `v6Only` defaults to false, so the
    // single resulting socket still accepts both v4 and v6.
    if (resolved == 'localhost') {
      return InternetAddress.anyIPv6.address;
    }
    return resolved;
  }

  static String _resolvedHost() {
    if (isRegistered(argsProvider)) {
      if (args.getOrNull<String>('host') case final value?) {
        return value;
      }
    }

    if (isRegistered(settingsProvider)) {
      if (settings.host case final value?) {
        return value;
      }
    }

    return 'localhost';
  }

  static int get port {
    if (isRegistered(argsProvider)) {
      if (args.getOrNull<int>('port') case final value?) {
        return value;
      }
    }

    if (isRegistered(settingsProvider)) {
      if (settings.port case final value?) {
        return value;
      }
    }

    return 8080;
  }
}
