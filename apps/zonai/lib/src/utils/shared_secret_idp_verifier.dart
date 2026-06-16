import 'dart:convert';

import 'package:clock/clock.dart' show clock;
import 'package:crypto/crypto.dart';
import 'package:zonai/src/exceptions/auth_exception.dart';
import 'package:zonai_schema/src/config/external_idp_config.dart';

/// Verifies JWTs against a [SharedSecretIdpConfig].
///
/// Pure logic — no I/O, no database access, no config resolver. Pins
/// HS256 at verification time so `alg=none` and confused-deputy attacks
/// are rejected at the type level. Validates the standard `iss`, `aud`,
/// `exp`, and `nbf` claims against the supplied config. Mapping the
/// returned claims onto a user record is the caller's job.
final class SharedSecretIdpVerifier {
  const SharedSecretIdpVerifier(this._config);

  final SharedSecretIdpConfig _config;

  /// Verifies [rawJwt] and returns its decoded payload claims.
  ///
  /// Throws [InvalidJwtException] for any failure: malformed input,
  /// wrong `alg`, bad signature, `iss`/`aud` mismatch, missing or
  /// expired `exp`, or `nbf` in the future.
  Map<String, Object?> verify(String rawJwt) {
    final parts = rawJwt.split('.');
    if (parts.length != 3) throw const InvalidJwtException();
    final headerSeg = parts[0];
    final payloadSeg = parts[1];
    final signatureSeg = parts[2];

    final header = _decodeSegment(headerSeg);
    final alg = header['alg'];
    if (alg is! String || alg.toUpperCase() != 'HS256') {
      throw const InvalidJwtException();
    }

    final actualSignature = _decodeBytes(signatureSeg);
    final signingInput = '$headerSeg.$payloadSeg';
    final expectedSignature = Hmac(
      sha256,
      utf8.encode(_config.secret),
    ).convert(utf8.encode(signingInput));
    if (!_timingSafeEq(expectedSignature.bytes, actualSignature)) {
      throw const InvalidJwtException();
    }

    final payload = _decodeSegment(payloadSeg);
    _validateStandardClaims(payload);
    return payload;
  }

  Map<String, Object?> _decodeSegment(String segment) {
    try {
      return jsonDecode(utf8.decode(base64Url.decode(_pad(segment))))
          as Map<String, Object?>;
    } on Object {
      throw const InvalidJwtException();
    }
  }

  List<int> _decodeBytes(String segment) {
    try {
      return base64Url.decode(_pad(segment));
    } on Object {
      throw const InvalidJwtException();
    }
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

  static String _pad(String s) {
    final padNeeded = (4 - s.length % 4) % 4;
    return padNeeded == 0 ? s : s + ('=' * padNeeded);
  }

  static bool _timingSafeEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
