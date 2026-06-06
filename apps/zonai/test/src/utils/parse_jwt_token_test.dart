import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';

import '../../../lib/src/utils/jwt_generator.dart';

void main() {
  const secret = 'rules-jwt-secret';
  late JwtGenerator generator;

  setUp(() => generator = JwtGenerator(jwtSecret: secret));

  group(normalizeJwtToken, () {
    test('strips Bearer prefix', () {
      expect(normalizeJwtToken('Bearer abc.def.ghi'), 'abc.def.ghi');
    });

    test('trims whitespace', () {
      expect(normalizeJwtToken('  token  '), 'token');
    });
  });

  group(parseJwtTokenClaimsOnly, () {
    test('returns null for absent token', () async {
      expect(await parseJwtTokenClaimsOnly(null), isNull);
      expect(await parseJwtTokenClaimsOnly(''), isNull);
      expect(await parseJwtTokenClaimsOnly('   '), isNull);
    });

    test('decodes a valid signed token', () async {
      await withClock(Clock.fixed(DateTime.utc(2020)), () async {
        final token = await generator.generate(
          Jwt.create(
            userId: 'user-1',
            table: 'users',
            user: {'email': 'a@b.com'},
            jwtId: JwtId('jwt-1'),
            expiresIn: const Duration(days: 1),
            claims: const {},
          ),
        );

        final jwt = await parseJwtTokenClaimsOnly(
          'Bearer $token',
          generator: generator,
        );

        expect(jwt?.userId.value, 'user-1');
        expect(jwt?.table, 'users');
      });
    });

    test('throws for invalid token', () async {
      await expectLater(
        parseJwtTokenClaimsOnly('not-a-jwt', generator: generator),
        throwsA(isA<StateError>()),
      );
    });
  });
}
