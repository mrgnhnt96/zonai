import 'dart:convert';

import 'package:clock/clock.dart' show clock;
import 'package:crypto/crypto.dart';

final class Jwt {
  const Jwt({required this.jwtPepper});

  final String jwtPepper;

  Future<String> generate({
    required String userId,
    required String collection,
    required String jwtId,
    required Duration expiresIn,
    required Map<String, Object?> claims,
  }) async {
    final header = <String, String>{'alg': 'HS256', 'typ': 'JWT'};
    final payload = <String, Object?>{
      'sub': userId,
      'col': collection,
      'jti': jwtId,
      'exp': clock.now().add(expiresIn).toUtc().millisecondsSinceEpoch ~/ 1000,
      'claims': _deepJson(claims),
    };
    final signingInput = '${_encodeSegment(header)}.${_encodeSegment(payload)}';
    final mac = Hmac(sha256, utf8.encode(jwtPepper));
    final signature = mac.convert(utf8.encode(signingInput)).bytes;
    return '$signingInput.${_bytesToBase64Url(signature)}';
  }

  /// Returns decoded payload maps (including `'claims'`), or null if invalid /
  /// tampered / expired / wrong algorithm.
  Future<Map<String, Object?>?> verify(String jwt) async {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    final signingInput = '${parts[0]}.${parts[1]}';

    Digest expected;
    try {
      expected = Hmac(
        sha256,
        utf8.encode(jwtPepper),
      ).convert(utf8.encode(signingInput));
    } on Object {
      return null;
    }

    List<int> actual;
    try {
      actual = base64Url.decode(_padBase64Url(parts[2]));
    } on Object {
      return null;
    }
    if (!_timingSafeEq(expected.bytes, actual)) return null;

    Map<String, Object?> headerObj;
    Map<String, Object?> payloadObj;
    try {
      headerObj = _decodeJwtPart(parts[0]) as Map<String, Object?>;
      payloadObj = _decodeJwtPart(parts[1]) as Map<String, Object?>;
    } on Object {
      return null;
    }

    final alg = headerObj['alg'];
    if (alg is! String || alg.toUpperCase() != 'HS256') return null;

    if (_isExpired(payloadObj['exp'])) return null;
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

  Object? _deepJson(Object? value) {
    if (value == null || value is bool || value is num || value is String) {
      return value;
    }
    if (value is Map<String, Object?>) {
      return {for (final e in value.entries) e.key: _deepJson(e.value)};
    }
    if (value is Map) {
      return {
        for (final e in value.entries) e.key.toString(): _deepJson(e.value),
      };
    }
    if (value is List<Object?>) {
      return [...value.map(_deepJson)];
    }
    if (value is List) {
      return [...value.map((e) => _deepJson(e))];
    }
    throw ArgumentError.value(
      value,
      'claims',
      'JWT claims must encode to JSON (bool, num, String, Map, List, null)',
    );
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
