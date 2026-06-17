import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jose/jose.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/config/external_idp_config.dart';

import '../../../lib/src/exceptions/auth_exception.dart';
import '../../../lib/src/utils/jwks_idp_verifier.dart';

const _issuer = 'https://issuer.example/auth';
const _audience = 'api.example.com';
const _jwksUrl = 'https://issuer.example/.well-known/jwks.json';

const _config = JwksIdpConfig(
  issuer: _issuer,
  audience: _audience,
  authTable: 'users',
  jwksUrl: _jwksUrl,
);

JwksIdpConfig _configWith({Duration? cacheTtl, Duration? fetchTimeout}) {
  return JwksIdpConfig(
    issuer: _issuer,
    audience: _audience,
    authTable: 'users',
    jwksUrl: _jwksUrl,
    cacheTtl: cacheTtl ?? const Duration(hours: 1),
    fetchTimeout: fetchTimeout ?? const Duration(seconds: 2),
  );
}

/// Builds an RSA key pair as a JWK and returns (signing key with private
/// material, JWKS-shaped public-only key, kid).
({JsonWebKey signingKey, Map<String, dynamic> publicJwk, String kid})
_makeRsaKeyPair({String kid = 'test-key-1'}) {
  final signing = JsonWebKey.generate('RS256');
  final publicSet = JsonWebKeySet.fromJson({
    'keys': [signing.toJson()],
  }).toJson();
  final publicJwk = Map<String, dynamic>.from(
    (publicSet['keys'] as List).first as Map,
  )..['kid'] = kid;
  publicJwk.removeWhere(
    (k, _) => const {'d', 'p', 'q', 'dp', 'dq', 'qi'}.contains(k),
  );

  // Re-construct the signing key with the kid attached so issued tokens
  // carry it in their protected header.
  final signingWithKid = JsonWebKey.fromJson(<String, dynamic>{
    ...signing.toJson(),
    'kid': kid,
  });

  return (signingKey: signingWithKid, publicJwk: publicJwk, kid: kid);
}

Future<String> _signedJwt({
  required JsonWebKey signingKey,
  required Map<String, Object?> payload,
  String alg = 'RS256',
}) async {
  final builder = JsonWebSignatureBuilder()
    ..jsonContent = payload
    ..addRecipient(signingKey, algorithm: alg);
  final jws = builder.build();
  return jws.toCompactSerialization();
}

void main() {
  final now = DateTime.utc(2026, 6, 17, 12, 0, 0);
  final nowSecs = now.millisecondsSinceEpoch ~/ 1000;

  Map<String, Object?> validPayload({
    String? iss,
    Object? aud,
    int? exp,
    int? nbf,
    String sub = 'user-1',
    Map<String, Object?> extra = const {},
  }) {
    return {
      'iss': iss ?? _issuer,
      'aud': aud ?? _audience,
      'exp': exp ?? nowSecs + 300,
      if (nbf != null) 'nbf': nbf,
      'sub': sub,
      ...extra,
    };
  }

  group(JwksIdpVerifier, () {
    test('verifies a valid RS256 token signed by a key in the JWKS', () async {
      final pair = _makeRsaKeyPair();
      final mockClient = MockClient((req) async {
        expect(req.url.toString(), _jwksUrl);
        return http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        );
      });
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      final token = await _signedJwt(
        signingKey: pair.signingKey,
        payload: validPayload(extra: {'role': 'admin'}),
      );

      await withClock(Clock.fixed(now), () async {
        final decoded = await verifier.verify(token);
        expect(decoded['iss'], _issuer);
        expect(decoded['aud'], _audience);
        expect(decoded['role'], 'admin');
      });
    });

    test(
      'rejects tokens whose alg is HS256 (not in the asymmetric allowlist)',
      () async {
        final pair = _makeRsaKeyPair();
        final mockClient = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'keys': [pair.publicJwk],
            }),
            200,
          ),
        );
        final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
        // Build a token with alg=HS256 manually so the verifier sees it
        // before any signature check happens.
        final hsToken = await _signedJwt(
          signingKey: JsonWebKey.fromJson({
            'kty': 'oct',
            'k': base64Url.encode(utf8.encode('shared-secret-not-rs')),
          }),
          payload: validPayload(),
          alg: 'HS256',
        );

        await withClock(Clock.fixed(now), () async {
          await expectLater(
            verifier.verify(hsToken),
            throwsA(isA<InvalidJwtException>()),
          );
        });
      },
    );

    test('rejects tokens whose alg is none', () async {
      final pair = _makeRsaKeyPair();
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        ),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      // Build a token with alg=none. jose may not let us build one
      // directly, so construct manually.
      final header = base64Url
          .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
          .replaceAll('=', '');
      final payload = base64Url
          .encode(utf8.encode(jsonEncode(validPayload())))
          .replaceAll('=', '');
      final token = '$header.$payload.';

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test(
      'rejects tokens whose `iss` does not match the configured issuer',
      () async {
        final pair = _makeRsaKeyPair();
        final mockClient = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'keys': [pair.publicJwk],
            }),
            200,
          ),
        );
        final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
        final token = await _signedJwt(
          signingKey: pair.signingKey,
          payload: validPayload(iss: 'https://attacker.example/auth'),
        );

        await withClock(Clock.fixed(now), () async {
          await expectLater(
            verifier.verify(token),
            throwsA(isA<InvalidJwtException>()),
          );
        });
      },
    );

    test('rejects tokens whose `aud` does not match (string form)', () async {
      final pair = _makeRsaKeyPair();
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        ),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      final token = await _signedJwt(
        signingKey: pair.signingKey,
        payload: validPayload(aud: 'other-api.example.com'),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test(
      'accepts tokens whose `aud` is a list containing the configured value',
      () async {
        final pair = _makeRsaKeyPair();
        final mockClient = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'keys': [pair.publicJwk],
            }),
            200,
          ),
        );
        final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
        final token = await _signedJwt(
          signingKey: pair.signingKey,
          payload: validPayload(aud: [_audience, 'other.example']),
        );

        await withClock(Clock.fixed(now), () async {
          expect(await verifier.verify(token), isA<Map<String, Object?>>());
        });
      },
    );

    test('rejects expired tokens', () async {
      final pair = _makeRsaKeyPair();
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        ),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      final token = await _signedJwt(
        signingKey: pair.signingKey,
        payload: validPayload(exp: nowSecs - 60),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens whose `nbf` is in the future', () async {
      final pair = _makeRsaKeyPair();
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        ),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      final token = await _signedJwt(
        signingKey: pair.signingKey,
        payload: validPayload(nbf: nowSecs + 60),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens whose `kid` is not in the JWKS', () async {
      final pair = _makeRsaKeyPair(kid: 'real-key');
      // Build a token whose kid is fabricated.
      final attackerKey = JsonWebKey.fromJson({
        ...JsonWebKey.generate('RS256').toJson(),
        'kid': 'fake-key',
      });
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        ),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      final token = await _signedJwt(
        signingKey: attackerKey,
        payload: validPayload(),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens when JWKS endpoint returns non-200', () async {
      final pair = _makeRsaKeyPair();
      final mockClient = MockClient(
        (_) async => http.Response('Server Error', 503),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      final token = await _signedJwt(
        signingKey: pair.signingKey,
        payload: validPayload(),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens when JWKS endpoint returns malformed JSON', () async {
      final pair = _makeRsaKeyPair();
      final mockClient = MockClient(
        (_) async => http.Response('not json at all', 200),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      final token = await _signedJwt(
        signingKey: pair.signingKey,
        payload: validPayload(),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('caches JWKS between calls; does not re-fetch within TTL', () async {
      final pair = _makeRsaKeyPair();
      var fetchCount = 0;
      final mockClient = MockClient((_) async {
        fetchCount++;
        return http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        );
      });
      final verifier = JwksIdpVerifier(
        _configWith(cacheTtl: const Duration(minutes: 10)),
        httpClient: mockClient,
      );
      final token = await _signedJwt(
        signingKey: pair.signingKey,
        payload: validPayload(),
      );

      await withClock(Clock.fixed(now), () async {
        await verifier.verify(token);
        await verifier.verify(token);
        await verifier.verify(token);
      });
      expect(fetchCount, 1);
    });

    test('re-fetches JWKS once the cache TTL has elapsed', () async {
      final pair = _makeRsaKeyPair();
      var fetchCount = 0;
      final mockClient = MockClient((_) async {
        fetchCount++;
        return http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        );
      });
      final verifier = JwksIdpVerifier(
        _configWith(cacheTtl: const Duration(minutes: 1)),
        httpClient: mockClient,
      );
      final token = await _signedJwt(
        signingKey: pair.signingKey,
        payload: validPayload(exp: nowSecs + 7200),
      );

      await withClock(Clock.fixed(now), () async {
        await verifier.verify(token);
      });
      expect(fetchCount, 1);

      // Advance the clock beyond the TTL and re-verify.
      final later = now.add(const Duration(minutes: 2));
      await withClock(Clock.fixed(later), () async {
        await verifier.verify(token);
      });
      expect(fetchCount, 2);
    });

    test(
      'refreshes the cache when a token presents a kid not in the cached set',
      () async {
        // First fetch: only key A. Second fetch: rotated key B added.
        final keyA = _makeRsaKeyPair(kid: 'kid-a');
        final keyB = _makeRsaKeyPair(kid: 'kid-b');
        var fetchCount = 0;
        final mockClient = MockClient((_) async {
          fetchCount++;
          final keys = fetchCount == 1
              ? [keyA.publicJwk]
              : [keyA.publicJwk, keyB.publicJwk];
          return http.Response(jsonEncode({'keys': keys}), 200);
        });
        final verifier = JwksIdpVerifier(
          _configWith(cacheTtl: const Duration(hours: 1)),
          httpClient: mockClient,
        );

        // First verification with keyA — populates the cache.
        final tokenA = await _signedJwt(
          signingKey: keyA.signingKey,
          payload: validPayload(),
        );
        // Second verification with keyB (rotated).
        final tokenB = await _signedJwt(
          signingKey: keyB.signingKey,
          payload: validPayload(),
        );

        await withClock(Clock.fixed(now), () async {
          await verifier.verify(tokenA);
          expect(fetchCount, 1);
          // tokenB's kid is not in the cached set → forces a refresh,
          // even though the TTL hasn't elapsed.
          await verifier.verify(tokenB);
          expect(fetchCount, 2);
        });
      },
    );

    test('rejects tokens signed by a key not in the JWKS', () async {
      final pair = _makeRsaKeyPair(kid: 'real-key');
      final imposterPair = _makeRsaKeyPair(kid: 'real-key');
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keys': [pair.publicJwk],
          }),
          200,
        ),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      // Same kid as the legitimate key, but signed by a different
      // private key — verification must fail at signature check.
      final token = await _signedJwt(
        signingKey: imposterPair.signingKey,
        payload: validPayload(),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects malformed JWTs (not three segments)', () async {
      final mockClient = MockClient(
        (_) async => http.Response(jsonEncode({'keys': []}), 200),
      );
      final verifier = JwksIdpVerifier(_config, httpClient: mockClient);
      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifier.verify('not-a-jwt'),
          throwsA(isA<InvalidJwtException>()),
        );
        await expectLater(
          verifier.verify('a.b'),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });
  });
}
