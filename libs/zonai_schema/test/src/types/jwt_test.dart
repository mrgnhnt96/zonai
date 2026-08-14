import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

String _encodeSegment(Object json) {
  // Matches how this library's own tokens are issued: base64url with the
  // RFC 7515 padding stripped.
  return base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
}

String _tokenFrom(Map<String, Object?> payload) {
  final header = _encodeSegment({'alg': 'HS256', 'typ': 'JWT'});
  final body = _encodeSegment(payload);
  return '$header.$body.signature';
}

void main() {
  group('Jwt.parse', () {
    test('returns null when the token is not three dot-separated parts', () {
      expect(Jwt.parse('not-a-jwt'), isNull);
      expect(Jwt.parse('a.b'), isNull);
      expect(Jwt.parse('a.b.c.d'), isNull);
    });

    test('decodes a real, unpadded base64url payload segment', () {
      final token = _tokenFrom(
        Jwt.create(
          userId: 'user-1',
          table: 'users',
          user: const {'email': 'a@example.com'},
          jwtId: JwtId('jwt-1'),
          expiresIn: const Duration(days: 1),
          claims: const {},
        ).toJson(),
      );

      final jwt = Jwt.parse(token);

      expect(jwt, isNotNull);
      expect(jwt!.userId.value, 'user-1');
      expect(jwt.table, 'users');
    });

    test('returns null, not throw, for a payload segment that is not JSON', () {
      // Three dot-separated parts, valid base64url, but the decoded payload
      // isn't JSON at all.
      final garbage = base64Url
          .encode(utf8.encode('not-json'))
          .replaceAll('=', '');
      final token = 'header.$garbage.signature';

      expect(() => Jwt.parse(token), returnsNormally);
      expect(Jwt.parse(token), isNull);
    });

    test('returns null, not throw, for JSON that is not a JWT object', () {
      final token =
          'header.${_encodeSegment(['not', 'an', 'object'])}.signature';

      expect(() => Jwt.parse(token), returnsNormally);
      expect(Jwt.parse(token), isNull);
    });

    test('returns null, not throw, for a payload missing required fields', () {
      final token = 'header.${_encodeSegment({'foo': 'bar'})}.signature';

      expect(() => Jwt.parse(token), returnsNormally);
      expect(Jwt.parse(token), isNull);
    });

    test('returns null, not throw, for invalid base64url characters', () {
      final token = 'header.not!valid!base64.signature';

      expect(() => Jwt.parse(token), returnsNormally);
      expect(Jwt.parse(token), isNull);
    });
  });
}
