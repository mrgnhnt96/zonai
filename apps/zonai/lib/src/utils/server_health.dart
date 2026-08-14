import 'package:http/http.dart' as http;

const defaultServerPort = 8080;

/// Host candidates to probe when checking if the zonai server is healthy.
///
/// Dart's HTTP client resolves `localhost` to IPv4 (`127.0.0.1`). On machines
/// where another process (e.g. Docker) owns that address, the real zonai
/// server listening on IPv6 loopback (`::1`) is missed. Try both loopbacks.
List<String> serverHealthHosts(String host) {
  // `ServerBinding.host` turns `localhost` into the any-address `::` so the
  // listener covers both families, and that value arrives here unchanged. A
  // wildcard is an address to LISTEN on and never one to connect to: Windows
  // refuses `connect()` to the unspecified address outright, so the probe
  // failed against a server that was listening and `zonai` reported it down.
  // macOS and Linux quietly redirect it to loopback, which is why this only
  // showed up once the suite ran on Windows. A socket bound to the wildcard
  // accepts on both loopbacks, so probing those asks the same question and
  // asks it portably.
  if (host == 'localhost' || _wildcardHosts.contains(host)) {
    return ['[::1]', '127.0.0.1', 'localhost'];
  }
  if (host.contains(':')) {
    return ['[$host]'];
  }
  return [host];
}

/// The addresses that mean "every interface" to `bind`, and nothing at all to
/// `connect`.
const _wildcardHosts = {'::', '0.0.0.0'};

/// Returns true when any candidate host responds 200 on `/health`.
Future<bool> checkZonaiServerHealth({
  String host = 'localhost',
  int port = defaultServerPort,
}) async {
  for (final candidate in serverHealthHosts(host)) {
    try {
      final result = await http.get(
        Uri.parse('http://$candidate:$port/health'),
      );
      if (result.statusCode == 200) return true;
    } catch (_) {}
  }
  return false;
}

String serverHealthUrl({
  String host = 'localhost',
  int port = defaultServerPort,
}) {
  final candidate = serverHealthHosts(host).first;
  return 'http://$candidate:$port/health';
}
