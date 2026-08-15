import 'package:clock/clock.dart' show clock;
import 'package:jose/jose.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider_kind.dart';

import 'oauth_exception.dart';

/// Signs Apple's OAuth2 `client_secret` — not a static string, but a fresh
/// ES256 JWT per token request (`iss: teamId`, `kid: keyId`, `sub: clientId`,
/// `aud: https://appleid.apple.com`), generated from the developer's `.p8`
/// key.
///
/// **Spike finding:** signing needs no new dependency. `package:jose`
/// (`^0.3.5`, already a dependency — `jwks_idp_verifier.dart` uses it for
/// verification) also signs: [JsonWebKey.fromPem] parses a PKCS8 PEM private
/// key — the exact format Apple's `.p8` file is — and
/// [JsonWebSignatureBuilder] produces a compact ES256 JWS from it. Confirmed
/// end-to-end: generated a real P-256 PKCS8 key with `openssl`, signed a JWT
/// with `jose`, and independently verified the signature with raw `openssl
/// dgst -verify` against the derived public key (not just round-tripped
/// through `jose`'s own verifier, which wouldn't rule out a symmetric bug).
///
/// Caches the signed JWT per (teamId, keyId, clientId) until it's within
/// [_refreshMargin] of expiry, per the design's "generate per token request,
/// cache until near expiry."
final class AppleClientSecretSigner {
  AppleClientSecretSigner({Duration expiresIn = const Duration(days: 150)})
    : _expiresIn = expiresIn {
    if (_expiresIn > _appleMaxExpiresIn) {
      throw ArgumentError.value(
        expiresIn,
        'expiresIn',
        'Apple rejects a client-secret JWT whose exp is more than 6 months '
            'past iat',
      );
    }
  }

  /// Apple's documented ceiling on the client-secret JWT's lifetime.
  static const _appleMaxExpiresIn = Duration(days: 180);

  /// Refresh this far ahead of expiry rather than exactly at it, so a
  /// request that starts just before expiry doesn't race a stale secret.
  static const _refreshMargin = Duration(minutes: 10);

  final Duration _expiresIn;
  final Map<String, _CachedSecret> _cache = {};

  /// Returns a valid client-secret JWT for [provider] (which must be
  /// [OAuthProviderKind.apple]), signing a fresh one if the cached value is
  /// missing or near expiry.
  String sign(BuiltInOAuthProvider provider) {
    if (provider.kind != OAuthProviderKind.apple) {
      throw ArgumentError.value(
        provider.kind,
        'provider',
        'AppleClientSecretSigner only signs OAuthProviderKind.apple providers',
      );
    }
    final teamId = provider.teamId;
    final keyId = provider.keyId;
    final privateKey = provider.privateKey;
    if (teamId == null || keyId == null || privateKey == null) {
      throw const OAuthAppleSigningException(
        'apple provider missing teamId/keyId/privateKey',
      );
    }

    final cacheKey = '$teamId:$keyId:${provider.clientId}';
    final now = clock.now().toUtc();
    final cached = _cache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(now.add(_refreshMargin))) {
      return cached.jwt;
    }

    final jwt = _signFresh(
      teamId: teamId,
      keyId: keyId,
      clientId: provider.clientId,
      privateKeyPem: privateKey,
      issuedAt: now,
    );
    _cache[cacheKey] = _CachedSecret(
      jwt: jwt.compact,
      expiresAt: jwt.expiresAt,
    );
    return jwt.compact;
  }

  ({String compact, DateTime expiresAt}) _signFresh({
    required String teamId,
    required String keyId,
    required String clientId,
    required String privateKeyPem,
    required DateTime issuedAt,
  }) {
    final expiresAt = issuedAt.add(_expiresIn);
    final iatSecs = issuedAt.millisecondsSinceEpoch ~/ 1000;
    final expSecs = expiresAt.millisecondsSinceEpoch ~/ 1000;

    final JsonWebKey key;
    try {
      key = JsonWebKey.fromPem(privateKeyPem, keyId: keyId);
    } on Object catch (e) {
      throw OAuthAppleSigningException('could not parse .p8 private key: $e');
    }

    final String compact;
    try {
      final builder = JsonWebSignatureBuilder()
        ..jsonContent = {
          'iss': teamId,
          'iat': iatSecs,
          'exp': expSecs,
          'aud': 'https://appleid.apple.com',
          'sub': clientId,
        }
        ..setProtectedHeader('alg', 'ES256')
        ..setProtectedHeader('kid', keyId)
        ..addRecipient(key, algorithm: 'ES256');
      compact = builder.build().toCompactSerialization();
    } on Object catch (e) {
      throw OAuthAppleSigningException('ES256 signing failed: $e');
    }

    return (compact: compact, expiresAt: expiresAt);
  }
}

final class _CachedSecret {
  const _CachedSecret({required this.jwt, required this.expiresAt});

  final String jwt;
  final DateTime expiresAt;
}
