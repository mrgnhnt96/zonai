// The browser leg, compiled by `dart compile js`.
//
// This is the production client stack, not an imitation of it. Everything
// below `RevaliClient.request` is the same code `apps/web` runs:
// `RevaliClient` -> `HttpPackageClient` -> `http.Client()` -> `BrowserClient`
// -> `window.fetch`. Only the two ends differ: the generated
// `MaintenanceDataSourceImpl.reclaimLogSpace` above it, which does nothing but
// decode the JSON envelope, and the outcome reporting below, which the real
// dashboard renders instead of posting back.
import 'dart:convert';
import 'dart:js_interop';

import 'package:revali_client/revali_client.dart';
import 'package:web/web.dart' as web;

/// [RevaliClient] requires storage for its session-cookie round trip. Nothing
/// in this probe authenticates, so an inert one is the honest choice -- a real
/// store would only add a variable that cannot change the redirect.
class _NoStorage implements Storage {
  const _NoStorage();

  @override
  Future<Object?> operator [](String key) async => null;

  @override
  Future<void> save(String key, Object? value) async {}

  @override
  Future<void> saveAll(Map<String, Object?> values) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> remove(String key) async {}
}

Future<void> main() async {
  final origin = web.window.location.origin;
  final client = RevaliClient(storage: const _NoStorage(), baseUrl: origin);

  final outcome = <String, Object?>{'stack': 'browser (BrowserClient/fetch)'};

  try {
    // The same call `MaintenanceDataSourceImpl.reclaimLogSpace` makes: POST,
    // this path, an `authorization` header, no body and no query.
    final response = await client.request(
      method: 'POST',
      path: '/dashboard/maintenance/reclaim-log-space',
      headers: {'authorization': 'probe'},
    );

    outcome['statusCode'] = response.statusCode;
    outcome['body'] = await response.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
  } catch (e) {
    // A non-2xx arrives here as `ServerException` -- `RevaliClient.request`
    // throws on any status outside 200..299, which includes a redirect the
    // transport did not follow. This is how the dashboard experiences it.
    outcome['errorType'] = e.runtimeType.toString();
    outcome['error'] = '$e';
    if (e is ServerException) {
      outcome['statusCode'] = e.statusCode;
    }
  }

  final json = jsonEncode(outcome);
  web.document.getElementById('out')?.textContent = json;

  // The server-side record is the evidence; this only carries the client's
  // view of the same exchange so both sides land in one artifact.
  await web.window
      .fetch('/report'.toJS, web.RequestInit(method: 'POST', body: json.toJS))
      .toDart;
}
