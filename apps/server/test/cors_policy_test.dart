import 'dart:async';
import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';

import '../routes/apps/dev_app.dart';

const _listed = 'https://app.example.com';
const _unlisted = 'https://customer.example';
const _loopback = 'http://localhost:8080';

/// Attaches [Cors] the way the generated server does.
final class _CorsWrapper implements RequestWrapper {
  const _CorsWrapper(this.policy);

  final CorsPolicy policy;

  @override
  WrapperResult wrap(Context context, NextResponse next) =>
      Cors(policy: policy).wrap(context, next);
}

/// Pins the CORS policy that replaced `@AllowOrigins.all()`.
///
/// The live behaviour being defended: revali_router's default [CorsPolicy]
/// reflects the caller's `Origin` with `Access-Control-Allow-Credentials: true`.
/// Left in place, a page on any domain could make credentialed calls here and
/// read the replies. `over a real connection` runs a preflight and a real
/// request through a router wired like the generated one, because a preflight
/// never reaches [Cors].
void main() {
  group('Cors component wiring', () {
    test('is typed as a LifecycleComponent, so it is actually generated', () {
      // Same failure mode as the bug fixed in 111b8dfd: without the `implements`
      // clause `@Cors()` still compiles, codegen still succeeds, and the
      // component contributes nothing at all -- silently.
      expect(
        const Cors(),
        isA<LifecycleComponent>(),
        reason:
            'without this the annotation is inert and every response '
            'keeps the reflected origin and credentials header',
      );
    });
  });

  group('over a real connection', () {
    late HttpServer server;
    late HttpClient client;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      client = HttpClient();

      final policy = ZonaiCorsPolicy(configured: () => {_listed});
      final router = Router(
        cors: policy,
        globalComponents: LifecycleComponentsImpl(
          requestWrappers: [_CorsWrapper(policy)],
        ),
        routes: [
          Route(
            'db',
            method: 'POST',
            handler: (context) async {
              context.response.statusCode = HttpStatus.ok;
            },
          ),
        ],
      );

      unawaited(handleRouterRequests(server, router, server.close));
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    Future<HttpClientResponse> send(String method, {String? origin}) async {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.port}/db'),
      );
      if (origin != null) request.headers.set('origin', origin);
      if (method == 'OPTIONS') {
        request.headers.set('access-control-request-method', 'POST');
      }

      final response = await request.close();
      await response.drain<void>();

      return response;
    }

    void expectGrant(
      HttpClientResponse response, {
      required String allowOrigin,
      required String? allowCredentials,
    }) {
      expect(response.statusCode, HttpStatus.ok);
      expect(
        response.headers.value('access-control-allow-origin'),
        allowOrigin,
      );
      expect(
        response.headers.value('access-control-allow-credentials'),
        allowCredentials,
      );
      expect(response.headers.value('vary'), 'Origin');
    }

    for (final method in ['OPTIONS', 'POST']) {
      group(method, () {
        test('gives an unlisted origin * without credentials', () async {
          expectGrant(
            await send(method, origin: _unlisted),
            allowOrigin: '*',
            allowCredentials: null,
          );
        });

        test('reflects a listed origin with credentials', () async {
          expectGrant(
            await send(method, origin: _listed),
            allowOrigin: _listed,
            allowCredentials: 'true',
          );
        });

        test('reflects a loopback origin with credentials', () async {
          expectGrant(
            await send(method, origin: _loopback),
            allowOrigin: _loopback,
            allowCredentials: 'true',
          );
        });
      });
    }

    test('varies on Origin for a request that sent none', () async {
      // A cache would otherwise replay this `*` to a listed origin, whose
      // credentialed request the browser would then refuse.
      expectGrant(await send('POST'), allowOrigin: '*', allowCredentials: null);
    });
  });

  group('ZonaiCorsPolicy', () {
    test('is what the app hands revali_router', () {
      expect(DevApp().cors, isA<ZonaiCorsPolicy>());
    });
  });

  group('decideCors', () {
    test('grants a loopback origin credentials', () {
      final decision = decideCors('http://localhost:8080');

      expect(decision.allowOrigin, 'http://localhost:8080');
      expect(decision.allowCredentials, isTrue);
    });

    test('grants an operator-configured origin credentials', () {
      final decision = decideCors(
        'https://app.example.com',
        configured: {'https://app.example.com'},
      );

      expect(decision.allowOrigin, 'https://app.example.com');
      expect(decision.allowCredentials, isTrue);
    });

    test('gives an unlisted origin the public wildcard, never credentials', () {
      // A web SDK runs on customer sites nobody can list. Withholding
      // Allow-Origin did not stop the request -- a POST was still stored --
      // it only showed the page a network error. And the original finding
      // still holds: an unlisted origin must never come back reflected, nor
      // with Access-Control-Allow-Credentials: true.
      final decision = decideCors('https://evil.example');

      expect(decision.allowOrigin, '*');
      expect(decision.allowCredentials, isFalse);
    });

    test('does not reflect an unlisted origin even when others are listed', () {
      final decision = decideCors(
        'https://customer.example',
        configured: {'https://app.example.com'},
      );

      expect(decision.allowOrigin, '*');
      expect(decision.allowCredentials, isFalse);
    });

    test('never reflects a lookalike of loopback', () {
      final decision = decideCors('https://localhost.evil.example');

      expect(decision.allowOrigin, '*');
      expect(decision.allowCredentials, isFalse);
    });

    test('never pairs a wildcard origin with credentials', () {
      // No Origin header: not a cross-origin browser request. `*` is fine on
      // its own, but `*` plus credentials would be a blanket grant.
      final decision = decideCors(null);

      expect(decision.allowOrigin, '*');
      expect(decision.allowCredentials, isFalse);
    });
  });

  group('isAllowedOrigin', () {
    test('accepts the origins the dashboard is served from', () {
      expect(isAllowedOrigin('http://localhost:8080'), isTrue);
      expect(isAllowedOrigin('http://127.0.0.1:8080'), isTrue);
      expect(isAllowedOrigin('http://[::1]:8080'), isTrue);
      expect(isAllowedOrigin('https://localhost'), isTrue);
    });

    test('rejects a hostile origin', () {
      expect(isAllowedOrigin('https://evil.example'), isFalse);
      expect(isAllowedOrigin('http://evil.example:8080'), isFalse);
    });

    test('is anchored, so a lookalike domain cannot slip through', () {
      // The pattern is matched with hasMatch, a substring test. Unanchored,
      // every one of these would be allowed -- and each is registrable.
      expect(isAllowedOrigin('https://localhost.evil.example'), isFalse);
      expect(isAllowedOrigin('https://evil.example/http://localhost'), isFalse);
      expect(isAllowedOrigin('https://not-localhost:8080'), isFalse);
      expect(isAllowedOrigin('http://127.0.0.1.evil.example'), isFalse);
    });

    test('does not treat the dots in an IP as regex wildcards', () {
      // `\.` written into generated source becomes a bare `.`, which matches
      // any character -- this is the corruption that took the allow-list off
      // the annotation and into a runtime regex.
      expect(isAllowedOrigin('http://127x0x0x1:8080'), isFalse);
    });
  });

  group('parseOrigins', () {
    test('is empty when unset, leaving only the loopback default', () {
      expect(parseOrigins(null), isEmpty);
      expect(parseOrigins('  '), isEmpty);
    });

    test('splits and trims a comma-separated list', () {
      expect(
        parseOrigins('https://app.example.com, https://admin.example.com'),
        {'https://app.example.com', 'https://admin.example.com'},
      );
    });
  });
}
