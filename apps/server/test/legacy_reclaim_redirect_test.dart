import 'dart:convert';
import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';

/// The kept legacy reclaim route must redirect in a way that survives being
/// followed, and "followed" here means by a browser.
///
/// `POST dashboard/maintenance/reclaim-log-space` was kept for compatibility
/// and answers with a redirect onto `reclaim-space`. That only works if the
/// second request is still a `POST`: every route on `MaintenanceController` is
/// `POST`-only by policy, and `Router._findMatch` matches on `(method,
/// segments)` -- so a downgraded redirect does not reach a handler with the
/// wrong method, it reaches no handler at all and 404s. This is the failure a
/// green unit suite would never notice, on the one path whose entire reason
/// for existing is that old clients keep working.
///
/// Three checks, in the order they would catch a regression:
///
///  1. the annotation is a method-preserving code (307/308, not 301/302/303);
///  2. served from the real [Router], a `GET` at the redirect target 404s and
///     a `POST` at it reaches the handler -- so (1) is load-bearing rather
///     than a style preference;
///  3. revali's generated route table carries the same code, because the
///     annotation is compiled by codegen and an annotation that contributes
///     nothing fails silently.
///
/// **What this file cannot check: that a real browser preserves the method.**
/// That is the browser's decision, not Dart's, and asserting it here would
/// mean writing the Fetch standard into the test and then reading it back.
/// It is measured for real in `e2e/legacy_reclaim_redirect`, which drives this
/// route tree from a compiled `package:http` `BrowserClient` in Chrome and
/// records what the server received. Against 302 the second request arrived as
/// `GET` and 404'd; against 307 it arrived as `POST` and reached the handler.
void main() {
  final controller = File('routes/controllers/maintenance_controller.dart');

  // Not a `skip`: this file is tracked, so its absence means the test is being
  // run from the wrong directory and every assertion below is void.
  if (!controller.existsSync()) {
    throw StateError(
      'expected ${controller.path} relative to the current directory '
      '(${Directory.current.path}) -- run this suite from apps/server',
    );
  }

  final annotation = RegExp(
    r"@Redirect\(\s*'([^']+)',\s*(\d+),?\s*\)\s*@Post\('reclaim-log-space'\)",
    dotAll: true,
  ).firstMatch(controller.readAsStringSync());

  test('the legacy reclaim route still carries a redirect annotation', () {
    // The route itself is not this suite's to defend -- the human decided it
    // stays -- but every assertion below reads through this match, so its
    // absence has to fail loudly rather than skip.
    expect(
      annotation,
      isNotNull,
      reason:
          'no @Redirect(...) @Post(\'reclaim-log-space\') in '
          '${controller.path}',
    );
  });

  final target = annotation?.group(1) ?? '';
  final code = int.tryParse(annotation?.group(2) ?? '') ?? -1;

  test('it redirects onto reclaim-space carrying both arguments', () {
    expect(target, startsWith('/dashboard/maintenance/reclaim-space?'));
    final query = Uri.parse(target).queryParameters;
    expect(query['target'], 'logdb');
    expect(query['min_reclaimable_bytes'], '16777216');
  });

  test('the redirect code preserves the method', () {
    expect(
      code,
      anyOf(307, 308),
      reason:
          'A $code does not preserve the method. Per the Fetch standard a '
          'browser rewrites a redirected POST into a GET on 301/302, and on '
          '303 always -- and reclaim-space is POST-only, so the redirected '
          'request would 404. Measured in e2e/legacy_reclaim_redirect: '
          'Chrome 151 turned a 302 here into GET reclaim-space -> 404. Use '
          '307 (or 308 for a permanent move).',
    );
  });

  group('served from the real router', () {
    late _Harness harness;

    setUpAll(() async => harness = await _Harness.start(target, code));
    tearDownAll(() async => harness.close());

    test('the legacy path answers with that code and Location', () async {
      final response = await harness.send(
        'POST',
        '/dashboard/maintenance/reclaim-log-space',
      );

      expect(response.statusCode, code);
      expect(response.headers.value(HttpHeaders.locationHeader), target);
    });

    test('a POST at the redirect target reaches the handler', () async {
      final response = await harness.send('POST', target);

      expect(response.statusCode, 200);
      expect(jsonDecode(await utf8.decoder.bind(response).join()), {
        'data': {
          'reached': 'reclaimSpace',
          'target': 'logdb',
          // An `int`, not the string from the URL: revali coerces a numeric
          // query value, which is what lets `reclaimSpace` bind it as
          // `@Query('min_reclaimable_bytes') required int`.
          'min_reclaimable_bytes': 16777216,
        },
      });
    });

    test('a GET at the redirect target reaches nothing', () async {
      // The consequence that makes the status code matter. `reclaim-space` is
      // POST-only on purpose -- "a GET that empties a table is one prefetch
      // away from doing it unasked" -- so a downgraded redirect is not a
      // different response, it is no route.
      final response = await harness.send('GET', target);

      expect(response.statusCode, 404);
    });
  });

  group('the generated route table actually carries it', () {
    // Reads revali's output rather than trusting the annotation: the wiring is
    // emitted, not written, and an annotation that contributes nothing fails
    // silently (known-issues.md #1).
    //
    // `.revali/` is gitignored, so it is absent on a clean CI runner and this
    // skips there. Named rather than hidden, exactly as
    // `confirm_rate_limit_test` names it.
    final route = File(
      '.revali/server/routes/__dashboard_maintenance_route.dart',
    );
    final skip = route.existsSync()
        ? null
        : 'no generated server here -- run `sip run server gen` (this '
              'assertion is skipped, not passed)';

    test('the emitted Route carries the same redirect', () {
      final source = route.readAsStringSync();
      final emitted = RegExp(
        r"'reclaim-log-space',(.*?)redirect: const Redirect\(\s*'([^']+)',\s*(\d+),?\s*\)",
        dotAll: true,
      ).firstMatch(source);

      expect(
        emitted,
        isNotNull,
        reason: 'no redirect emitted for the legacy route',
      );
      expect(emitted!.group(2), target);
      expect(int.parse(emitted.group(3)!), code);
    }, skip: skip);
  });
}

/// A real [HttpServer] running the real [Router] over the reclaim routes.
///
/// Only the two paths and their methods are reproduced from what revali's
/// codegen emits for `MaintenanceController`; the DI, components and argument
/// binding around them are left out because neither half of the mechanism
/// under test touches them. `RunRedirect` answers before `execute.run()`, and
/// `Router._findMatch` runs before either.
class _Harness {
  _Harness._(this._server, this._client);

  final HttpServer _server;
  final HttpClient _client;

  static Future<_Harness> start(String target, int code) async {
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
                context.response.body = {
                  'data': {'reached': 'reclaimLogSpace'},
                };
              },
              redirect: Redirect(target, code),
            ),
          ],
        ),
      ],
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.forEach(router.handleRequest);

    // `followRedirects` off on purpose: this suite is asking what the SERVER
    // said and what each method does at the target, one hop at a time. Letting
    // the client decide would fold its own redirect policy -- which is not the
    // browser's -- into the answer.
    final client = HttpClient()..autoUncompress = false;

    return _Harness._(server, client);
  }

  Future<HttpClientResponse> send(String method, String path) async {
    final request =
        await _client.openUrl(
            method,
            Uri.parse('http://127.0.0.1:${_server.port}$path'),
          )
          ..followRedirects = false
          ..headers.set(HttpHeaders.authorizationHeader, 'probe');

    return request.close();
  }

  void close() {
    _client.close(force: true);
    _server.close(force: true);
  }
}
