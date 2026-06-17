import 'dart:convert';

import 'package:clock/clock.dart' show clock;
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:zonai/src/exceptions/auth_exception.dart';
import 'package:zonai_schema/src/config/external_idp_config.dart';

/// Verifies JWTs against a [JwksIdpConfig].
///
/// Fetches the IdP's JWKS endpoint on demand and caches the parsed
/// key set for [JwksIdpConfig.cacheTtl]. Instances are intended to
/// outlive a single request — the cache only does its job when the
/// verifier is shared across calls for the same [JwksIdpConfig].
///
/// **Algorithm pinning:** rejects any `alg` outside `RS256` / `RS384`
/// / `RS512` / `ES256` / `ES384` / `ES512`. Blocks `alg=none` and the
/// classic confused-deputy attack where an HMAC verifier is handed
/// an asymmetric public key.
///
/// **Key rotation:** if a token's `kid` is not in the cached key
/// set, the cache is refreshed once — newly-rotated keys land on the
/// next request without waiting for the TTL. To bound amplification,
/// kid-miss refreshes are floored to one attempt per
/// [_kidMissRefreshFloor]; further kid misses inside the window are
/// rejected without re-fetching.
///
/// **DoS posture:** [JwksIdpConfig.fetchTimeout] bounds the per-call
/// HTTP wait. A failing IdP cannot indefinitely block auth.
/// [JwksIdpConfig.jwksUrl] must be `https://`; plaintext JWKS lets a
/// network attacker substitute keys and forge any token.
final class JwksIdpVerifier {
  JwksIdpVerifier(this._config, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final JwksIdpConfig _config;
  final http.Client _httpClient;
  _JwksCacheEntry? _cache;
  DateTime? _lastKidMissRefresh;

  /// Minimum time between kid-miss-driven refreshes. Bounds the
  /// amplification surface where a stream of tokens with random
  /// unknown `kid` values would otherwise force one JWKS fetch per
  /// token. TTL-driven refreshes are not gated by this floor.
  static const _kidMissRefreshFloor = Duration(seconds: 10);

  /// Releases the underlying HTTP client. Safe to call multiple times.
  void dispose() {
    _httpClient.close();
  }

  /// Algorithms whose JWS signatures this verifier accepts. HMAC
  /// algorithms (`HS*`) are intentionally rejected — they presume a
  /// shared secret and don't belong on a JWKS path.
  static const _allowedAlgorithms = <String>{
    'RS256',
    'RS384',
    'RS512',
    'ES256',
    'ES384',
    'ES512',
  };

  /// Verifies [rawJwt] and returns its decoded payload claims.
  ///
  /// Throws [InvalidJwtException] for any failure: malformed input,
  /// unsupported `alg`, no matching JWKS key, bad signature, missing
  /// `iss`/`aud`, expired `exp`, `nbf` in the future, or unreachable
  /// JWKS endpoint.
  Future<Map<String, Object?>> verify(String rawJwt) async {
    final JsonWebSignature jws;
    try {
      jws = JsonWebSignature.fromCompactSerialization(rawJwt);
    } on Object {
      throw const InvalidJwtException();
    }

    final unverified = jws.unverifiedPayload;
    final header = unverified.protectedHeader?.toJson() ?? const {};

    final alg = header['alg'];
    if (alg is! String || !_allowedAlgorithms.contains(alg)) {
      throw const InvalidJwtException();
    }

    final kid = switch (header['kid']) {
      final String value => value,
      _ => null,
    };

    final keyStore = await _getKeyStore(requestedKid: kid);

    final bool verified;
    try {
      verified = await jws.verify(keyStore);
    } on Object {
      throw const InvalidJwtException();
    }
    if (!verified) throw const InvalidJwtException();

    final Map<String, Object?> claims;
    try {
      claims = jsonDecode(unverified.stringContent) as Map<String, Object?>;
    } on Object {
      throw const InvalidJwtException();
    }

    _validateStandardClaims(claims);
    return claims;
  }

  /// Returns a [JsonWebKeyStore] usable for verification.
  ///
  /// If the cached set is fresh and contains [requestedKid] (when
  /// the token presented one), it's returned directly. Otherwise the
  /// JWKS is re-fetched — except that a kid-miss with an otherwise-
  /// fresh cache only triggers a refresh once per
  /// [_kidMissRefreshFloor], so a stream of tokens with bogus `kid`s
  /// cannot drive unbounded JWKS fetches. A miss after the refresh
  /// throws: the token references a key the IdP doesn't advertise.
  Future<JsonWebKeyStore> _getKeyStore({required String? requestedKid}) async {
    final cache = _cache;
    final cacheFresh = cache != null && !cache.isExpired();
    final cacheContainsKid =
        requestedKid == null || (cache?.kids.contains(requestedKid) ?? false);

    if (cacheFresh && cacheContainsKid) {
      return cache!.keyStore;
    }

    if (cacheFresh && !cacheContainsKid) {
      // kid miss with a fresh cache: allow one refresh per floor
      // window. A legitimate key rotation only needs one fetch to
      // pick up the new kid; rapid-fire kid misses after that are
      // the amplification pattern this floor blocks.
      final lastKidMiss = _lastKidMissRefresh;
      if (lastKidMiss != null &&
          clock.now().difference(lastKidMiss) < _kidMissRefreshFloor) {
        throw const InvalidJwtException();
      }
      _lastKidMissRefresh = clock.now();
    }

    await _refreshCache();
    final refreshed = _cache;
    if (refreshed == null) throw const InvalidJwtException();
    if (requestedKid != null && !refreshed.kids.contains(requestedKid)) {
      throw const InvalidJwtException();
    }
    return refreshed.keyStore;
  }

  /// Fetches the JWKS endpoint and rebuilds the cache.
  ///
  /// Throws [InvalidJwtException] on a non-`https://` URL, network
  /// error, timeout, non-200 status, malformed JSON, or a missing
  /// `keys` array; the previous cache (if any) is left untouched.
  Future<void> _refreshCache() async {
    final Uri uri;
    try {
      uri = Uri.parse(_config.jwksUrl);
    } on Object {
      throw const InvalidJwtException();
    }
    if (uri.scheme != 'https') {
      throw const InvalidJwtException();
    }

    final http.Response resp;
    try {
      resp = await _httpClient.get(uri).timeout(_config.fetchTimeout);
    } on Object {
      throw const InvalidJwtException();
    }
    if (resp.statusCode != 200) {
      throw const InvalidJwtException();
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } on Object {
      throw const InvalidJwtException();
    }

    final rawKeys = body['keys'];
    if (rawKeys is! List) throw const InvalidJwtException();

    final keyStore = JsonWebKeyStore();
    final kids = <String>{};
    for (final raw in rawKeys) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        keyStore.addKey(JsonWebKey.fromJson(raw));
      } on Object {
        // Skip malformed key entries — a broken row shouldn't kill
        // the whole refresh.
        continue;
      }
      final kid = raw['kid'];
      if (kid is String) kids.add(kid);
    }

    _cache = _JwksCacheEntry(
      keyStore: keyStore,
      kids: kids,
      fetchedAt: clock.now(),
      ttl: _config.cacheTtl,
    );
  }

  void _validateStandardClaims(Map<String, Object?> payload) {
    if (payload['iss'] != _config.issuer) {
      throw const InvalidJwtException();
    }
    final aud = payload['aud'];
    final audMatches = switch (aud) {
      String s => s == _config.audience,
      List l => l.contains(_config.audience),
      _ => false,
    };
    if (!audMatches) throw const InvalidJwtException();

    final nowSecs = clock.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final exp = payload['exp'];
    if (exp is! num || exp.toInt() < nowSecs) {
      throw const InvalidJwtException();
    }
    final nbf = payload['nbf'];
    if (nbf is num && nbf.toInt() > nowSecs) {
      throw const InvalidJwtException();
    }
  }
}

final class _JwksCacheEntry {
  _JwksCacheEntry({
    required this.keyStore,
    required this.kids,
    required this.fetchedAt,
    required this.ttl,
  });

  final JsonWebKeyStore keyStore;
  final Set<String> kids;
  final DateTime fetchedAt;
  final Duration ttl;

  bool isExpired() => clock.now().difference(fetchedAt) >= ttl;
}
