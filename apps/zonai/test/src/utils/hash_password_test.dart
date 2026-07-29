import 'dart:convert';
import 'dart:typed_data';

import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';

import '../../../lib/deps.dart';
import '../../../lib/src/utils/hash_password.dart';

/// Low-cost parameters so Argon2 remains correct but tests stay fast.
const _testPasswordSecret = 'test-app-secret';
final _hasher = HashPassword(
  passwordSecret: _testPasswordSecret,
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

    test('verification succeeds using a rolled-off secret', () async {
      const oldSecret = 'old-secret';
      const newSecret = 'new-secret';
      final enrolled = HashPassword(
        passwordSecret: oldSecret,
        memoryKiB: 64,
        iterations: 1,
        parallelism: 1,
        hashLength: 32,
        saltLength: 16,
      );
      final login = HashPassword(
        passwordSecret: newSecret,
        previousPasswordSecrets: [oldSecret],
        memoryKiB: 64,
        iterations: 1,
        parallelism: 1,
        hashLength: 32,
        saltLength: 16,
      );
      final encoded = await enrolled.hash(password: 'secret', salt: fixedSalt);
      expect(
        await login.verify(passwordHash: encoded, rawPassword: 'secret'),
        isTrue,
      );
    });

    test(
      'verification fails when a different instance uses the wrong secret',
      () async {
        const rightSecret = 'right-secret';
        const wrongSecret = 'wrong-secret';
        final enrollment = HashPassword(
          passwordSecret: rightSecret,
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
          hashLength: 32,
          saltLength: 16,
        );
        final login = HashPassword(
          passwordSecret: wrongSecret,
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
        'is deterministic for the same password, secret, and salt',
        () async {
          final a = await _hasher.hash(password: 'secret', salt: fixedSalt);
          final b = await _hasher.hash(password: 'secret', salt: fixedSalt);
          expect(a, b);
        },
      );

      test('changes when password secret changes', () async {
        const secretA = 'secret-a-instance';
        const secretB = 'secret-b-instance';
        final hasherA = HashPassword(
          passwordSecret: secretA,
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
          hashLength: 32,
          saltLength: 16,
        );
        final hasherB = HashPassword(
          passwordSecret: secretB,
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

  group('native Argon2 backend', () {
    // The native path needs the `fs` scoped_deps provider (to locate the
    // compiled library on disk) -- every other test in this file runs
    // outside any scope, so it silently falls back to the pure-Dart path
    // instead of erroring. This group explicitly provides a scope so the
    // native path actually runs, guarding the one property that matters
    // most: it must produce byte-identical output to the pure-Dart path,
    // since existing password hashes were (and, without a built native
    // library, still may be) produced by that path.
    test(
      'produces output identical to a fixed-salt pure-Dart reference hash',
      () async {
        // Recorded once from the pure-Dart path (parallelism: 1, so this
        // exact call is also what the native path would be asked to
        // reproduce) -- see hash_password.dart's `_argon2DigestPureDart`.
        const fixedSalt = [
          0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
          0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
          // dart format off
        ];
        const expectedPureDartEncoding =
            'AAECAwQFBgcICQoLDA0ODw==./uSVNjFQNTcKCSpsi4HzkP2IMIgqGLoX19PcLnYgp0U=';

        final encoded = await runMergedScopedFuture(
          () => _hasher.hash(password: 'native-vs-pure-dart', salt: fixedSalt),
          override: {fsProvider.overrideWith(LocalFileSystem.new)},
        );

        expect(encoded, expectedPureDartEncoding);
      },
    );
  });
}
