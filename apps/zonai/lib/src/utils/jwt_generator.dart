import 'dart:convert';

import 'package:clock/clock.dart' show clock;
import 'package:crypto/crypto.dart';
import 'package:zonai/src/deps/config_resolver.dart';
import 'package:zonai_schema/src/types/jwt.dart';

final class JwtGenerator {
  JwtGenerator({
    String? jwtSecret,
    List<String> previousJwtSecrets = const [],
  }) : _explicitJwtSecret = jwtSecret,
       _explicitPreviousJwtSecrets = previousJwtSecrets;

  final String? _explicitJwtSecret;
  final List<String> _explicitPreviousJwtSecrets;

  List<String>? _cachedJwtSecretsForVerify;

  Future<List<String>> _jwtSecretsForVerify() async {
    if (_cachedJwtSecretsForVerify case final cached?) {
      return cached;
    }
    if (_explicitJwtSecret == null && _explicitPreviousJwtSecrets.isNotEmpty) {
      throw StateError(
        'previousJwtSecrets is only valid with jwtSecret when not using config',
      );
    }
    if (_explicitJwtSecret case final explicit?) {
      return _cachedJwtSecretsForVerify = [
        explicit,
        ..._explicitPreviousJwtSecrets,
      ];
    }
    final config = await configResolver.resolve();
    return _cachedJwtSecretsForVerify =
        List<String>.unmodifiable(config.jwtSecretsForVerify);
  }

  Future<String> get jwtSecret async => (await _jwtSecretsForVerify()).first;

  Future<String> generate(Jwt jwt) async {
    final header = <String, String>{'alg': 'HS256', 'typ': 'JWT'};
    final payload = jwt.toJson();
    final signingInput = '${_encodeSegment(header)}.${_encodeSegment(payload)}';
    final mac = Hmac(sha256, utf8.encode(await jwtSecret));
    final signature = mac.convert(utf8.encode(signingInput)).bytes;
    return '$signingInput.${_bytesToBase64Url(signature)}';
  }

  /// Returns decoded payload maps (including `'claims'`), or null if invalid /
  /// tampered / expired / wrong algorithm.
  Future<Map<String, Object?>?> verify(String jwt) async {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    final [header, payload, signature] = parts;
    final signingInput = '${header}.${payload}';

    List<int> actual;
    try {
      actual = base64Url.decode(_padBase64Url(signature));
    } on Object {
      return null;
    }

    var verifiedDigest = false;
    for (final secret in await _jwtSecretsForVerify()) {
      Digest expected;
      try {
        expected = Hmac(
          sha256,
          utf8.encode(secret),
        ).convert(utf8.encode(signingInput));
      } on Object {
        continue;
      }
      if (_timingSafeEq(expected.bytes, actual)) {
        verifiedDigest = true;
        break;
      }
    }
    if (!verifiedDigest) return null;

    Map<String, Object?> headerObj;
    Map<String, Object?> payloadObj;
    try {
      headerObj = _decodeJwtPart(header) as Map<String, Object?>;
      payloadObj = _decodeJwtPart(payload) as Map<String, Object?>;
    } on Object {
      return null;
    }

    final alg = headerObj['alg'];
    if (alg is! String || alg.toUpperCase() != 'HS256') return null;

    final expSec = payloadObj['exp'] ?? payloadObj['expiresAt'];
    if (_isExpired(expSec)) return null;
    return payloadObj;
  }

  bool _isExpired(Object? exp) {
    final nowSecs = clock.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    switch (exp) {
      case final int secs:
        return secs < nowSecs;
      case final num n:
        return n.toInt() < nowSecs;
      default:
        return exp != null;
    }
  }

  String _encodeSegment(Map<String, Object?> payload) =>
      _bytesToBase64Url(utf8.encode(jsonEncode(payload)));

  Object _decodeJwtPart(String segment) =>
      jsonDecode(utf8.decode(base64Url.decode(_padBase64Url(segment))));

  String _bytesToBase64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  String _padBase64Url(String s) {
    final m = s.length % 4;
    if (m == 0) return s;
    return s + '=' * (4 - m);
  }

  bool _timingSafeEq(List<int> expected, List<int> actual) {
    if (expected.length != actual.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected[i] ^ actual[i];
    }
    return diff == 0;
  }
}
