import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_server/config/server_binding.dart';

void main() {
  group('ServerBinding.host', () {
    test('defaults to loopback, not an address reachable from the network', () {
      // This used to default to InternetAddress.anyIPv6, which binds *every*
      // interface -- a laptop on an untrusted network was serving the whole
      // network with nothing having asked it to. Loopback is the default
      // because exposing a server should be something someone chose.
      expect(ServerBinding.host, InternetAddress.loopbackIPv4.address);
    });

    test('the default binding accepts loopback', () async {
      final server = await HttpServer.bind(ServerBinding.host, 0);
      addTearDown(server.close);

      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      ).timeout(const Duration(seconds: 2));
      addTearDown(socket.destroy);
    });

    test('the default binding is NOT reachable on a non-loopback address',
        () async {
      // The property that actually matters, and the one the previous default
      // silently lost. Asserting the address string alone would keep passing
      // if the rewrite came back somewhere else in the chain.
      final server = await HttpServer.bind(ServerBinding.host, 0);
      addTearDown(server.close);

      final external = await _firstNonLoopbackIPv4();
      if (external == null) {
        // Nothing to prove it against on a machine with no external IPv4.
        return;
      }

      await expectLater(
        Socket.connect(
          external,
          server.port,
        ).timeout(const Duration(seconds: 2)),
        throwsA(isA<Exception>()),
        reason:
            'a server bound to loopback must refuse connections addressed to '
            'this machine\'s LAN address -- if this passes, the bind is '
            'exposing the network again',
      );
    });
  });
}

/// This machine's first non-loopback IPv4 address, if it has one.
Future<InternetAddress?> _firstNonLoopbackIPv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback) return address;
    }
  }

  return null;
}
