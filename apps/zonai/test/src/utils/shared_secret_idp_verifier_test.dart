import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/config/external_idp_config.dart';

import '../../../lib/src/exceptions/auth_exception.dart';
import '../../../lib/src/utils/shared_secret_idp_verifier.dart';

/// Builds an HS256 JWT with the supplied [header] and [payload], signed
/// with [secret]. Mirrors the segment/padding rules in
/// [SharedSecretIdpVerifier].
String _signedJwt({
  required String secret,
  required Map<String, Object?> header,
  required Map<String, Object?> payload,
}) {
  final h = base64Url
      .encode(utf8.encode(jsonEncode(header)))
      .replaceAll('=', '');
  final p = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  final signingInput = '$h.$p';
  final mac = Hmac(sha256, utf8.encode(secret));
  final sig = base64Url
      .encode(mac.convert(utf8.encode(signingInput)).bytes)
      .replaceAll('=', '');
  return '$signingInput.$sig';
}

void main() {
  const config = SharedSecretIdpConfig(
    issuer: 'https://issuer.example/auth',
    audience: 'api.example.com',
    authTable: 'users',
    secret: 'shared-secret',
  );

  const verifier = SharedSecretIdpVerifier(config);

  final now = DateTime.utc(2026, 6, 16, 12, 0, 0);
  final nowSecs = now.millisecondsSinceEpoch ~/ 1000;
  final futureExp = nowSecs + 300; // 5 minutes from "now"
  final pastExp = nowSecs - 60; // 1 minute before "now"

  Map<String, Object?> validPayload({
    String? iss,
    Object? aud,
    int? exp,
    int? nbf,
    String sub = 'user-1',
    Map<String, Object?> extra = const {},
  }) {
    return {
      'iss': iss ?? config.issuer,
      'aud': aud ?? config.audience,
      'exp': exp ?? futureExp,
      if (nbf != null) 'nbf': nbf,
      'sub': sub,
      ...extra,
    };
  }

  Map<String, Object?> validHeader() {
    return const {'alg': 'HS256', 'typ': 'JWT'};
  }

  group(SharedSecretIdpVerifier, () {
    test('returns the payload when signature, alg, and claims are valid', () {
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(extra: {'role': 'admin', 'n': 42}),
      );
      withClock(Clock.fixed(now), () {
        final decoded = verifier.verify(token);
        expect(decoded['iss'], config.issuer);
        expect(decoded['aud'], config.audience);
        expect(decoded['sub'], 'user-1');
        expect(decoded['role'], 'admin');
        expect(decoded['n'], 42);
      });
    });

    test('accepts aud as a list that contains the configured audience', () {
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(aud: [config.audience, 'other.example.com']),
      );
      withClock(Clock.fixed(now), () {
        expect(verifier.verify(token), isA<Map<String, Object?>>());
      });
    });

    test('rejects malformed input (not three dot-separated segments)', () {
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify('not-a-jwt'),
          throwsA(isA<InvalidJwtException>()),
        );
        expect(
          () => verifier.verify('a.b'),
          throwsA(isA<InvalidJwtException>()),
        );
        expect(
          () => verifier.verify('a.b.c.d'),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects garbage segments that fail base64/json decoding', () {
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify('!!!.???.@@@'),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens whose alg is not HS256 (blocks alg=none)', () {
      final token = _signedJwt(
        secret: config.secret,
        header: const {'alg': 'none', 'typ': 'JWT'},
        payload: validPayload(),
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens whose alg is RS256 (confused-deputy guard)', () {
      final token = _signedJwt(
        secret: config.secret,
        header: const {'alg': 'RS256', 'typ': 'JWT'},
        payload: validPayload(),
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens signed with a different secret', () {
      final token = _signedJwt(
        secret: 'wrong-secret',
        header: validHeader(),
        payload: validPayload(),
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tampered payload (signature mismatch)', () {
      final originalToken = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(),
      );
      final parts = originalToken.split('.');
      final tamperedPayload = base64Url
          .encode(utf8.encode(jsonEncode(validPayload(sub: 'attacker'))))
          .replaceAll('=', '');
      final tampered = '${parts[0]}.$tamperedPayload.${parts[2]}';
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(tampered),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens with wrong issuer', () {
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(iss: 'https://attacker.example/auth'),
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens with wrong audience (string form)', () {
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(aud: 'other-api.example.com'),
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens with wrong audience (list form)', () {
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(aud: ['a', 'b']),
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens missing aud entirely', () {
      final payload = validPayload()..remove('aud');
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: payload,
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens missing exp entirely', () {
      final payload = validPayload()..remove('exp');
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: payload,
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects expired tokens', () {
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(exp: pastExp),
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects tokens whose nbf is in the future', () {
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(nbf: nowSecs + 60),
      );
      withClock(Clock.fixed(now), () {
        expect(
          () => verifier.verify(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('accepts tokens with nbf in the past', () {
      final token = _signedJwt(
        secret: config.secret,
        header: validHeader(),
        payload: validPayload(nbf: nowSecs - 60),
      );
      withClock(Clock.fixed(now), () {
        expect(verifier.verify(token)['nbf'], nowSecs - 60);
      });
    });
  });
}
