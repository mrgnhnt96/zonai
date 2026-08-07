import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_server/config/server_binding.dart';

void main() {
  group('ServerBinding.host', () {
    test('defaults to the IPv6 any-address, not a hostname', () {
      // 'localhost' is resolved by the platform DNS resolver, which is free
      // to return an AAAA record first (macOS does) and bind IPv6-loopback
      // only -- IPv4 loopback and Android's 10.0.2.2 then get "Connection
      // refused" with no cue that it's a binding-family issue. Binding the
      // literal any-address sidesteps resolver order entirely.
      expect(ServerBinding.host, InternetAddress.anyIPv6.address);
    });

    test('binds reachably on both IPv4 and IPv6 loopback', () async {
      final server = await HttpServer.bind(ServerBinding.host, 0);
      addTearDown(server.close);

      final v4 = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      ).timeout(const Duration(seconds: 2));
      addTearDown(v4.destroy);

      final v6 = await Socket.connect(
        InternetAddress.loopbackIPv6,
        server.port,
      ).timeout(const Duration(seconds: 2));
      addTearDown(v6.destroy);
    });
  });
}
