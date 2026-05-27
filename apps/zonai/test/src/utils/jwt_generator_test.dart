import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/types/jwt.dart';

import '../../../lib/src/utils/jwt_generator.dart';

/// Matches [JwtGenerator]'s HS256 segments (same base64url / padding rules).
String _manualJwt({
  required String jwtSecret,
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
  final mac = Hmac(sha256, utf8.encode(jwtSecret));
  final digest = mac.convert(utf8.encode(signingInput));
  final sig = base64Url.encode(digest.bytes).replaceAll('=', '');
  return '$signingInput.$sig';
}

void main() {
  const pepper = 'test-jwt-pepper';
  late JwtGenerator jwt;

  setUp(() => jwt = JwtGenerator(jwtSecret: pepper));

  group(JwtGenerator, () {
    test('generate then verify preserves payload shape', () async {
      const expiresIn = Duration(days: 365);
      await withClock(Clock.fixed(DateTime.utc(2020)), () async {
        final token = await jwt.generate(
          Jwt.create(
            userId: 'user-42',
            table: 'things',
            user: {},
            jwtId: 'jti-ab',
            expiresIn: expiresIn,
            claims: {'role': 'admin', 'n': 1, 'nested': <String, Object?>{}},
          ),
        );
        expect(token.split('.').length, 3);

        final decoded = await jwt.verify(token);
        expect(decoded, isNotNull);
        expect(decoded!['userId'], 'user-42');
        expect(decoded['table'], 'things');
        expect(decoded['jwtId'], 'jti-ab');
        expect(
          decoded['expiresAt'],
          DateTime.utc(2020).add(expiresIn).toUtc().millisecondsSinceEpoch ~/
              1000,
        );

        final outClaims = decoded['claims'];
        expect(outClaims, isA<Map>());
        expect((outClaims as Map)['role'], 'admin');
        expect(outClaims['n'], 1);
        expect(outClaims['nested'], isA<Map>());
        expect(outClaims['nested'], isEmpty);
      });
    });

    test('supports nested maps and lists in claims', () async {
      final claims = <String, Object?>{
        'items': ['a', 2, true],
        'meta': <String, Object?>{'k': null},
      };
      final token = await jwt.generate(
        Jwt.create(
          userId: 'u',
          table: 'c',
          user: {},
          jwtId: 'j',
          expiresIn: const Duration(days: 365000),
          claims: claims,
        ),
      );
      final decoded = await jwt.verify(token);
      expect(decoded, isNotNull);
      final roundTrip = decoded!['claims'];
      expect(roundTrip, isA<Map>());
      expect((roundTrip as Map)['meta'], claims['meta']);
      expect(roundTrip['items'], claims['items']);
    });

    test('expiresAt respects UTC normalization', () async {
      final anchor = DateTime.utc(2099, 1, 2, 15, 30);
      await withClock(Clock.fixed(anchor), () async {
        const expiresIn = Duration(days: 365000);
        final token = await jwt.generate(
          Jwt.create(
            userId: 'u',
            table: 'c',
            user: {},
            jwtId: 'j',
            expiresIn: expiresIn,
            claims: {},
          ),
        );
        final decoded = (await jwt.verify(token))!;
        expect(
          decoded['expiresAt'],
          anchor.toUtc().add(expiresIn).millisecondsSinceEpoch ~/ 1000,
        );
      });
    });

    group('#verify rejects', () {
      test('when signature does not verify (wrong pepper)', () async {
        final token = await jwt.generate(
          Jwt.create(
            userId: 'u',
            table: 'c',
            user: {},
            jwtId: 'j',
            expiresIn: const Duration(days: 365000),
            claims: {},
          ),
        );
        expect(
          await JwtGenerator(jwtSecret: 'other-secret').verify(token),
          isNull,
        );
      });

      test('accepts token signed with a rolled-off pepper', () async {
        const oldPepper = 'jwt-pepper-v1';
        const newPepper = 'jwt-pepper-v2';
        await withClock(Clock.fixed(DateTime.utc(2020)), () async {
          final legacyToken = _manualJwt(
            jwtSecret: oldPepper,
            header: const {'alg': 'HS256', 'typ': 'JWT'},
            payload: {
              'sub': 'u',
              'col': 'c',
              'usr': {},
              'jti': 'j',
              'exp':
                  DateTime.utc(
                    2020,
                  ).add(const Duration(days: 365000)).millisecondsSinceEpoch ~/
                  1000,
              'claims': <String, Object?>{},
            },
          );
          final decoded = await JwtGenerator(
            jwtSecret: newPepper,
            previousJwtSecrets: [oldPepper],
          ).verify(legacyToken);
          expect(decoded, isNotNull);
          expect(decoded!['sub'], 'u');
        });
      });

      test('malformed JWT (missing segments)', () async {
        expect(await jwt.verify(''), isNull);
        expect(await jwt.verify('only-one'), isNull);
        expect(await jwt.verify('a.b'), isNull);
      });

      test('bogus base64 segment', () async {
        expect(
          await jwt.verify(
            '${base64Url.encode(utf8.encode('{}')).replaceAll('=', '')}.'
            '${base64Url.encode(utf8.encode('{}')).replaceAll('=', '')}.%%%',
          ),
          isNull,
        );
      });

      test('when payload was tampered with', () async {
        final token = await jwt.generate(
          Jwt.create(
            userId: 'original',
            table: 'c',
            user: {},
            jwtId: 'j',
            expiresIn: const Duration(days: 365000),
            claims: {},
          ),
        );
        final p2 = token.split('.');
        final bytes = base64Url.decode(
          '${p2[1]}${'=' * ((4 - p2[1].length % 4) % 4)}',
        );
        bytes[bytes.length - 1] ^= 0xff;
        p2[1] = base64Url.encode(bytes).replaceAll('=', '');
        expect(await jwt.verify(p2.join('.')), isNull);
      });

      test('when signature slice was tampered with', () async {
        final token = await jwt.generate(
          Jwt.create(
            userId: 'u',
            table: 'c',
            user: {},
            jwtId: 'j',
            expiresIn: const Duration(days: 365000),
            claims: {},
          ),
        );
        final parts = token.split('.');
        var sigBytes = base64Url.decode(
          '${parts[2]}${'=' * ((4 - parts[2].length % 4) % 4)}',
        );
        sigBytes[sigBytes.length - 1] ^= 1;
        parts[2] = base64Url.encode(sigBytes).replaceAll('=', '');
        expect(await jwt.verify(parts.join('.')), isNull);
      });

      test('when alg is valid MAC but header alg is not HS256', () async {
        final token = _manualJwt(
          jwtSecret: pepper,
          header: {'alg': 'HS512', 'typ': 'JWT'},
          payload: {
            'sub': 'x',
            'col': 'c',
            'jti': 'j',
            'exp': 4666886400,
            'claims': <String, Object?>{},
          },
        );
        expect(await jwt.verify(token), isNull);
      });

      test('when exp is in the past', () async {
        await withClock(Clock.fixed(DateTime.utc(2099)), () async {
          final token = await jwt.generate(
            Jwt.create(
              userId: 'u',
              table: 'c',
              user: {},
              jwtId: 'j',
              expiresIn: const Duration(days: -365),
              claims: {},
            ),
          );
          expect(await jwt.verify(token), isNull);
        });
      });

      test('when token not yet expired (same frozen clock)', () async {
        await withClock(Clock.fixed(DateTime.utc(2099)), () async {
          const ttl = Duration(hours: 1);
          final token = await jwt.generate(
            Jwt.create(
              userId: 'u',
              table: 'c',
              user: {},
              jwtId: 'j',
              expiresIn: ttl,
              claims: {},
            ),
          );
          expect(await jwt.verify(token), isNotNull);
        });
      });

      test('when exp field has unsupported type after JSON decode', () async {
        final token = _manualJwt(
          jwtSecret: pepper,
          header: {'alg': 'HS256', 'typ': 'JWT'},
          payload: {
            'sub': 'x',
            'col': 'c',
            'jti': 'j',
            'exp': '2077-01-01',
            'claims': <String, Object?>{},
          },
        );
        expect(await jwt.verify(token), isNull);
      });

      test('when header JSON is garbage', () async {
        final notJson = base64Url
            .encode(utf8.encode('not-json'))
            .replaceAll('=', '');
        final payloadSegment = base64Url
            .encode(
              utf8.encode(
                jsonEncode({
                  'sub': 'u',
                  'col': 'c',
                  'jti': 'j',
                  'exp': 4666886400,
                  'claims': <String, Object?>{},
                }),
              ),
            )
            .replaceAll('=', '');
        final signingInput = '$notJson.$payloadSegment';
        final mac = Hmac(sha256, utf8.encode(pepper));
        final sig = base64Url
            .encode(mac.convert(utf8.encode(signingInput)).bytes)
            .replaceAll('=', '');
        expect(await jwt.verify('$signingInput.$sig'), isNull);
      });
    });

    group('#generate', () {
      test('reject non JSON-encodable claim values', () async {
        await expectLater(
          jwt.generate(
            Jwt.create(
              userId: 'u',
              table: 'c',
              user: {},
              jwtId: 'j',
              expiresIn: const Duration(days: 365),
              claims: {'bad': Object()},
            ),
          ),
          throwsA(isA<JsonUnsupportedObjectError>()),
        );
      });
    });

    group('payload without exp (manual JWT)', () {
      test('verify succeeds when MAC and alg are OK', () async {
        final token = _manualJwt(
          jwtSecret: pepper,
          header: {'alg': 'HS256', 'typ': 'JWT'},
          payload: {
            'sub': 'u',
            'col': 'c',
            'jti': 'j',
            'claims': <String, Object?>{},
          },
        );
        final decoded = await jwt.verify(token);
        expect(decoded, isNotNull);
        expect(decoded!['sub'], 'u');
      });
    });
  });
}
