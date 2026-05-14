import 'dart:convert';

import 'package:clock/clock.dart' show clock;
import 'package:crypto/crypto.dart';
import 'package:zonai_schema/src/types/jwt.dart';

final class JwtGenerator {
  const JwtGenerator({required this.jwtPepper});

  final String jwtPepper;

  Future<String> generate(Jwt jwt) async {
    final header = <String, String>{'alg': 'HS256', 'typ': 'JWT'};
    final payload = jwt.toJson();
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
    final [header, payload, signature] = parts;
    final signingInput = '${header}.${payload}';

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
      actual = base64Url.decode(_padBase64Url(signature));
    } on Object {
      return null;
    }
    if (!_timingSafeEq(expected.bytes, actual)) return null;

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
