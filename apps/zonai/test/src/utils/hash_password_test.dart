import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../../lib/src/utils/hash_password.dart';

/// Low-cost parameters so Argon2 remains correct but tests stay fast.
const _testPepper = 'test-app-pepper';
const _hasher = HashPassword(
  passwordPepper: _testPepper,
  memoryKiB: 64,
  iterations: 1,
  parallelism: 1,
  hashLength: 32,
  saltLength: 16,
);

void main() {
  group(HashPassword, () {
    // dart format off
    final fixedSalt = Uint8List.fromList([
      0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
      0x0c, 0x0d, 0x0e, 0x0f,
    ]);
    // dart format on

    test(
      'same password verifies successfully against stored encoding',
      () async {
        const password = 'correct-horse-battery-staple';
        final encoded = await _hasher.hash(password: password);
        expect(
          await _hasher.verify(passwordHash: encoded, rawPassword: password),
          isTrue,
        );
      },
    );

    test('wrong password fails verification', () async {
      final encoded = await _hasher.hash(password: 'secret');
      expect(
        await _hasher.verify(passwordHash: encoded, rawPassword: 'wrong'),
        isFalse,
      );
    });

    test(
      'same password produces different encodings when salts differ',
      () async {
        const password = 'same-password';
        final a = await _hasher.hash(password: password);
        final b = await _hasher.hash(password: password);
        expect(a, isNot(b));
      },
    );

    test(
      'verification fails when a different instance uses the wrong pepper',
      () async {
        const rightPepper = 'right-pepper';
        const wrongPepper = 'wrong-pepper';
        final enrollment = const HashPassword(
          passwordPepper: rightPepper,
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
          hashLength: 32,
          saltLength: 16,
        );
        final login = const HashPassword(
          passwordPepper: wrongPepper,
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
          hashLength: 32,
          saltLength: 16,
        );
        final encoded = await enrollment.hash(password: 'secret');
        expect(
          await login.verify(passwordHash: encoded, rawPassword: 'secret'),
          isFalse,
        );
      },
    );

    test(
      'verification reuses stored salt from encoding, not a newly generated one',
      () async {
        final enrollment = await _hasher.hash(password: 'secret');
        expect(
          await _hasher.verify(passwordHash: enrollment, rawPassword: 'secret'),
          isTrue,
        );
      },
    );

    test(
      'replacing only the salt segment breaks verification (digest bound to stored salt)',
      () async {
        final otherSalt = Uint8List.fromList(List<int>.filled(16, 0xab));
        final encoded = await _hasher.hash(password: 'p', salt: fixedSalt);
        final dot = encoded.indexOf('.');
        expect(dot, greaterThan(0));
        final digestPart = encoded.substring(dot + 1);
        final tampered = '${base64Encode(otherSalt)}.$digestPart';
        expect(
          await _hasher.verify(passwordHash: tampered, rawPassword: 'p'),
          isFalse,
        );
      },
    );

    group('#hash', () {
      test(
        'is deterministic for the same password, pepper, and salt',
        () async {
          final a = await _hasher.hash(password: 'secret', salt: fixedSalt);
          final b = await _hasher.hash(password: 'secret', salt: fixedSalt);
          expect(a, b);
        },
      );

      test('changes when pepper changes', () async {
        const pepperA = 'pepper-a-instance';
        const pepperB = 'pepper-b-instance';
        final hasherA = HashPassword(
          passwordPepper: pepperA,
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
          hashLength: 32,
          saltLength: 16,
        );
        final hasherB = HashPassword(
          passwordPepper: pepperB,
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
          hashLength: 32,
          saltLength: 16,
        );
        final a = await hasherA.hash(password: 'secret', salt: fixedSalt);
        final b = await hasherB.hash(password: 'secret', salt: fixedSalt);
        expect(a, isNot(b));
      });

      test('changes when password changes', () async {
        final pa = await _hasher.hash(password: 'secret-a', salt: fixedSalt);
        final pb = await _hasher.hash(password: 'secret-b', salt: fixedSalt);
        expect(pa, isNot(pb));
      });

      test('stored form is saltBase64.digestBase64 only', () async {
        final encoded = await _hasher.hash(password: 'x', salt: fixedSalt);
        expect(encoded, isNot(contains(r'$')));
        final parts = encoded.split('.');
        expect(parts.length, 2);
        expect(parts[0], isNotEmpty);
        expect(parts[1], isNotEmpty);
        expect(base64.decode(parts[0]), fixedSalt);
        expect(parts[1], matches(RegExp(r'^[A-Za-z0-9+/]+=*$')));
      });
    });

    group('#verify', () {
      test('returns false for malformed encoding', () async {
        expect(
          await _hasher.verify(
            passwordHash: 'not-a-phc-string',
            rawPassword: 'x',
          ),
          isFalse,
        );
      });

      test(
        'returns false when digest length does not match instance hashLength',
        () async {
          final shortDigestB64 = base64Encode([1, 2, 3, 3, 7]);
          final saltB64 = base64Encode(fixedSalt);
          final bad = '$saltB64.$shortDigestB64';
          expect(
            await _hasher.verify(passwordHash: bad, rawPassword: 'x'),
            isFalse,
          );
        },
      );
    });
  });

  group('generateSecureSalt', () {
    test('supports requested length', () {
      expect(_hasher.generateSecureSalt(16), hasLength(16));
      expect(_hasher.generateSecureSalt(32), hasLength(32));
    });

    test('two salts are not byte-identical (high probability)', () {
      final a = _hasher.generateSecureSalt(16);
      final b = _hasher.generateSecureSalt(16);
      expect(a, isNot(b));
    });
  });
}
