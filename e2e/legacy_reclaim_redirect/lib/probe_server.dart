import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:revali_router/revali_router.dart';

/// One request as the SERVER saw it, before any handler ran.
///
/// The whole harness exists to answer "what arrived", so this is recorded off
/// the raw [HttpRequest] in the accept loop rather than inside a route
/// handler: a request that matches no route never reaches a handler, and that
/// is precisely the outcome under test.
class ReceivedRequest {
  const ReceivedRequest({
    required this.method,
    required this.path,
    required this.query,
  });

  final String method;
  final String path;
  final String query;

  /// Path and query as one string, which is how the redirect target is
  /// written and therefore how it is easiest to compare.
  String get target => query.isEmpty ? path : '$path?$query';

  @override
  String toString() => '$method $target';
}

/// The `dashboard/maintenance` reclaim routes, served by the real
/// [Router] from `revali_router`.
///
/// The route tree below is transcribed from what revali's codegen emits for
/// [MaintenanceController] -- `apps/server/.revali/server/routes/__dashboard_maintenance_route.dart`,
/// which is gitignored, so it cannot simply be imported. What is reproduced
/// is only the part that decides this leaf's question: the two paths, their
/// `method: 'POST'`, and the [Redirect] on the legacy one. Everything the
/// generated file wraps around that -- DI, rate limits, argument binding, the
/// handler bodies -- is left out because none of it participates in either
/// half of the mechanism under test. Redirects are answered by
/// `RunRedirect` *before* `execute.run()`, and route matching is done by
/// `Router._findMatch(segments, method)` before that.
///
/// So the 302 (or 307) on the wire here is revali's own, produced by
/// `CannedResponse.redirect`, not a hand-rolled one -- which is what makes an
/// observation against this server evidence about production.
class ProbeServer {
  ProbeServer._(this._server, this.received);

  final HttpServer _server;

  /// Every request this server received, oldest first.
  final List<ReceivedRequest> received;

  /// Completes with the JSON the browser leg posts back to `/report`.
  final Completer<String> browserReport = Completer<String>();

  static const legacyPath = '/dashboard/maintenance/reclaim-log-space';
  static const newPath = '/dashboard/maintenance/reclaim-space';
  static const redirectTarget =
      '$newPath?target=logdb&min_reclaimable_bytes=16777216';

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  /// Starts the harness on an ephemeral port.
  ///
  /// [redirectCode] is the status the legacy route answers with, so the same
  /// harness can be run against the 302 the human asked for and the 307 that
  /// preserves the method, and the two observations compared.
  static Future<ProbeServer> start({
    required int redirectCode,
    String? browserProbeJs,
  }) async {
    final received = <ReceivedRequest>[];

    final router = Router(
      routes: [
        Route(
          'dashboard/maintenance',
          routes: [
            Route(
              'reclaim-space',
              method: 'POST',
              handler: (context) async {
                context.response.body = {
                  'data': {
                    'reached': 'reclaimSpace',
                    'target': context.request.queryParameters['target'],
                    'min_reclaimable_bytes': context
                        .request
                        .queryParameters['min_reclaimable_bytes'],
                  },
                };
              },
            ),
            Route(
              'reclaim-log-space',
              method: 'POST',
              handler: (context) async {
                // Unreachable while the route carries a redirect, exactly as
                // in production. Kept so that removing the redirect makes
                // this harness report the handler being reached rather than
                // failing to compile.
                context.response.body = {
                  'data': {'reached': 'reclaimLogSpace'},
                };
              },
              redirect: Redirect(redirectTarget, redirectCode),
            ),
          ],
        ),
      ],
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final probe = ProbeServer._(server, received);

    unawaited(
      server.forEach((request) {
        received.add(
          ReceivedRequest(
            method: request.method,
            path: request.uri.path,
            query: request.uri.query,
          ),
        );

        // Static assets for the browser leg are answered here rather than by
        // the router: they are scaffolding for the observation, not part of
        // the surface being observed.
        if (browserProbeJs != null &&
            probe._serveBrowserAssets(request, browserProbeJs)) {
          return;
        }

        unawaited(router.handleRequest(request));
      }),
    );

    return probe;
  }

  /// Answers the browser leg's page, its compiled script, and the endpoint it
  /// posts its outcome back to. Returns whether the request was handled.
  bool _serveBrowserAssets(HttpRequest request, String js) {
    switch (request.uri.path) {
      case '/':
        request.response
          ..headers.contentType = ContentType.html
          ..write(_browserProbePage);
        unawaited(request.response.close());
        return true;
      case '/probe.js':
        request.response
          ..headers.contentType = ContentType('application', 'javascript')
          ..write(js);
        unawaited(request.response.close());
        return true;
      case '/report':
        unawaited(
          utf8.decoder.bind(request).join().then((body) {
            browserReport.complete(body);
            request.response
              ..statusCode = 204
              ..close();
          }),
        );
        return true;
      default:
        return false;
    }
  }

  Future<void> close() => _server.close(force: true);
}

const _browserProbePage = '''
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>legacy reclaim redirect probe</title></head>
  <body>
    <h1>legacy reclaim redirect probe</h1>
    <pre id="out">running...</pre>
    <script defer src="/probe.js"></script>
  </body>
</html>
''';
