import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:zonai/src/utils/oauth/oauth_pkce.dart';

/// `≥128 bits` of entropy, base64url-decoded (no padding), is at least 16
/// bytes.
const _minEntropyBytes = 16;

void main() {
  group('generateOAuthState', () {
    test('produces a URL-safe token with at least 128 bits of entropy', () {
      final state = generateOAuthState();
      expect(
        base64Url.decode(_pad(state)).length,
        greaterThanOrEqualTo(_minEntropyBytes),
      );
      expect(state, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('is different on every call', () {
      final values = List.generate(50, (_) => generateOAuthState());
      expect(values.toSet(), hasLength(50));
    });
  });

  group('generateOAuthNonce', () {
    test('produces a URL-safe token with at least 128 bits of entropy', () {
      final nonce = generateOAuthNonce();
      expect(
        base64Url.decode(_pad(nonce)).length,
        greaterThanOrEqualTo(_minEntropyBytes),
      );
    });

    test('is different on every call', () {
      final values = List.generate(50, (_) => generateOAuthNonce());
      expect(values.toSet(), hasLength(50));
    });
  });

  group('generatePkceCodeVerifier', () {
    test('is within RFC 7636\'s 43-128 character length bound', () {
      final verifier = generatePkceCodeVerifier();
      expect(verifier.length, inInclusiveRange(43, 128));
    });

    test('uses only RFC 7636\'s unreserved-character alphabet', () {
      final verifier = generatePkceCodeVerifier();
      expect(verifier, matches(RegExp(r'^[A-Za-z0-9._~-]+$')));
    });
  });

  group('derivePkceCodeChallenge', () {
    test('matches BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final expected = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

      expect(derivePkceCodeChallenge(verifier), expected);
    });

    test('is the well-known RFC 7636 appendix B example', () {
      // RFC 7636 §B: the spec's own worked example.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expectedChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      expect(derivePkceCodeChallenge(verifier), expectedChallenge);
    });

    test('is deterministic for the same input', () {
      final verifier = generatePkceCodeVerifier();
      expect(
        derivePkceCodeChallenge(verifier),
        derivePkceCodeChallenge(verifier),
      );
    });
  });
}

String _pad(String s) {
  final mod = s.length % 4;
  return mod == 0 ? s : s + ('=' * (4 - mod));
}
