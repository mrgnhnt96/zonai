import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/settings.dart';

/// Default host and port when not overridden by CLI args.
abstract final class ServerBinding {
  /// The address actually handed to `HttpServer.bind`.
  ///
  /// Whatever the operator names is bound verbatim -- naming a host is how you
  /// ask to be reachable there, and rewriting it silently is how a server ends
  /// up listening somewhere nobody chose. Only the *default* is translated,
  /// and only to loopback: an unconfigured server is reachable from this
  /// machine and nowhere else. Exposing it externally is an explicit act
  /// (`--host 0.0.0.0`, or `host:` in settings), not what you get by leaving
  /// the field blank.
  ///
  /// The default is the IPv4 loopback literal rather than the string
  /// 'localhost' because a hostname goes through the platform resolver, which
  /// is free to hand back an AAAA record first (macOS does) and bind
  /// IPv6-loopback *only* -- leaving IPv4 loopback, and Android's 10.0.2.2
  /// (which the emulator maps to the host's 127.0.0.1), with no listener at
  /// all: "Connection refused", with nothing pointing at address family as
  /// the cause. Binding the literal sidesteps resolver order entirely and
  /// keeps the emulator case working.
  ///
  /// This previously defaulted to [InternetAddress.anyIPv6] to cover both
  /// families at once. That does bind v4 and v6 from one socket, but the
  /// any-address binds *every* interface -- so a machine on a coffee-shop LAN
  /// was serving the whole network, with no setting having asked for it. The
  /// v6 loopback client is the cost of that fix: reach it with `--host ::1`.
  static String get host {
    final resolved = _resolvedHost();

    if (resolved == 'localhost') {
      return InternetAddress.loopbackIPv4.address;
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
