import 'package:http/http.dart' as http;

const defaultServerPort = 8080;

/// Host candidates to probe when checking if the zonai server is healthy.
///
/// Both loopbacks are tried for `localhost` and for the wildcards, and only
/// for those. Dart's HTTP client resolves `localhost` to IPv4 (`127.0.0.1`),
/// so on a machine where another process (e.g. Docker) owns that address the
/// real zonai server listening on IPv6 loopback (`::1`) would be missed.
///
/// Any other host is returned as the single candidate it is — including
/// `127.0.0.1`, which is what `ServerBinding.host` now answers for the
/// default. A concrete address is taken at its word rather than widened: the
/// caller binds and probes the same value, so there is nothing to reconcile,
/// and probing a sibling loopback would only invite a false "healthy" from
/// an unrelated process holding it.
List<String> serverHealthHosts(String host) {
  // A wildcard is an address to LISTEN on and never one to connect to:
  // Windows refuses `connect()` to the unspecified address outright, so the
  // probe failed against a server that was listening and `zonai` reported it
  // down. macOS and Linux quietly redirect it to loopback, which is why this
  // only showed up once the suite ran on Windows. A socket bound to the
  // wildcard accepts on both loopbacks, so probing those asks the same
  // question and asks it portably.
  //
  // What reaches this branch has changed, and the note that used to sit here
  // was left describing the old world. `ServerBinding.host` no longer turns
  // `localhost` into the any-address `::` -- since the bind-exposure fix it
  // answers `127.0.0.1` -- so the wildcard case is now reached by an explicit
  // `host:` in the project config, not by the default.
  //
  // The narrowing that follows is deliberate. `127.0.0.1` matches neither the
  // `localhost` case nor a wildcard, so it falls through to the
  // single-candidate return below and `::1` is never probed.
  //
  // That is correct, and widening it would be the bug. `Revali.health()`
  // dials `ServerBinding.host`, which is the same value the server binds, so
  // the two agree by construction and there is nothing to reconcile. Probing
  // the sibling loopback as well would only add a way to answer "healthy"
  // because some *other* process holds `::1`.
  //
  // What made this look like a defect was a test binding `localhost` and
  // expecting the probe to find it: `bind('localhost')` takes whichever
  // family the resolver puts first (`::1` on macOS) while the probe correctly
  // dialled `127.0.0.1`. That was a mismatch the test invented and production
  // does not have; it now binds `ServerBinding.host` too.
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
