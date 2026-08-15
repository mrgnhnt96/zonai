import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Random bytes behind `state`, `nonce`, and the PKCE `code_verifier`: 32
/// bytes is 256 bits, well above the design's ≥128-bit floor.
const _randomByteCount = 32;

/// A cryptographically random `state` value for the authorization request.
/// Persisted hashed (never in plaintext) per §4.1 of the OAuth design.
String generateOAuthState() => _randomUrlSafeToken();

/// A cryptographically random OIDC `nonce`, bound into the `id_token` and
/// checked against on verification.
String generateOAuthNonce() => _randomUrlSafeToken();

/// A PKCE `code_verifier` per RFC 7636 §4.1 — base64url (no padding) is a
/// subset of the spec's unreserved-character alphabet, so this is valid
/// as-is.
String generatePkceCodeVerifier() => _randomUrlSafeToken();

/// Derives the S256 `code_challenge` for [codeVerifier] per RFC 7636 §4.2:
/// `BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))`.
String derivePkceCodeChallenge(String codeVerifier) {
  final digest = sha256.convert(ascii.encode(codeVerifier));
  return _base64UrlNoPad(digest.bytes);
}

String _randomUrlSafeToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(
    _randomByteCount,
    (_) => random.nextInt(256),
  );
  return _base64UrlNoPad(bytes);
}

String _base64UrlNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
