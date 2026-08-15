import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai/src/utils/server_health.dart';

void main() {
  group('serverHealthHosts', () {
    test('localhost probes both loopback families and the name itself', () {
      expect(serverHealthHosts('localhost'), [
        '[::1]',
        '127.0.0.1',
        'localhost',
      ]);
    });

    // `ServerBinding.host` maps `localhost` onto the any-address so the
    // listener covers both families, and that is the value the health probe
    // is handed. Connecting to it is not portable: Windows rejects
    // `connect()` to the unspecified address, which reported a server that
    // was listening as down (`revali_health_test`, cli (windows-latest)).
    // Named from `InternetAddress` rather than a literal so this keeps
    // agreeing with what `ServerBinding` actually produces.
    test('the IPv6 any-address is probed as loopback, never as itself', () {
      expect(
        serverHealthHosts(InternetAddress.anyIPv6.address),
        isNot(contains('[::]')),
      );
      expect(serverHealthHosts(InternetAddress.anyIPv6.address), [
        '[::1]',
        '127.0.0.1',
        'localhost',
      ]);
    });

    test('the IPv4 any-address is probed as loopback, never as itself', () {
      expect(serverHealthHosts(InternetAddress.anyIPv4.address), [
        '[::1]',
        '127.0.0.1',
        'localhost',
      ]);
    });

    test('a real IPv6 literal is bracketed and probed as given', () {
      expect(serverHealthHosts('::1'), ['[::1]']);
      expect(serverHealthHosts('fe80::1'), ['[fe80::1]']);
    });

    test('any other host is probed exactly as configured', () {
      expect(serverHealthHosts('10.0.0.4'), ['10.0.0.4']);
      expect(serverHealthHosts('db.internal'), ['db.internal']);
    });
  });

  group('serverHealthUrl', () {
    test('names a connectable address for a wildcard binding', () {
      expect(
        serverHealthUrl(host: InternetAddress.anyIPv6.address, port: 3000),
        'http://[::1]:3000/health',
      );
    });
  });
}
