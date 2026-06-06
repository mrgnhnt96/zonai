import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_web/utils/jwt_payload.dart';

String _fakeJwt(Map<String, Object?> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '');
  final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$header.$body.signature';
}

void main() {
  group('decodeJwtPayload', () {
    test('returns null for malformed tokens', () {
      expect(decodeJwtPayload('not-a-jwt'), isNull);
      expect(decodeJwtPayload('a.b'), isNull);
    });

    test('decodes payload segment', () {
      final payload = decodeJwtPayload(
        _fakeJwt({
          'userId': 'u1',
          'user': {'email': 'a@b.com'},
        }),
      );
      expect(payload?['userId'], 'u1');
      expect((payload?['user'] as Map)['email'], 'a@b.com');
    });
  });

  group('sessionUserFromToken', () {
    test('extracts email and admin flag', () {
      final user = sessionUserFromToken(
        _fakeJwt({
          'userId': 'u1',
          'user': {'email': 'admin@example.com'},
          'admin': {'isAdmin': true},
        }),
      );

      expect(user?.email, 'admin@example.com');
      expect(user?.label, 'admin@example.com');
      expect(user?.initial, 'A');
      expect(user?.isAdmin, isTrue);
      expect(user?.canEdit, isFalse);
    });

    test('extracts canEdit when present', () {
      final user = sessionUserFromToken(
        _fakeJwt({
          'userId': 'u1',
          'admin': {'isAdmin': true, 'canEdit': true},
        }),
      );

      expect(user?.isAdmin, isTrue);
      expect(user?.canEdit, isTrue);
    });

    test('canEdit is false when absent or explicitly false', () {
      expect(
        sessionUserFromToken(
          _fakeJwt({
            'userId': 'u1',
            'admin': {'isAdmin': true},
          }),
        )?.canEdit,
        isFalse,
      );
      expect(
        sessionUserFromToken(
          _fakeJwt({
            'userId': 'u1',
            'admin': {'canEdit': false},
          }),
        )?.canEdit,
        isFalse,
      );
    });

    test('falls back to userId when email is missing', () {
      final user = sessionUserFromToken(_fakeJwt({'userId': 'user-42', 'user': {}}));
      expect(user?.label, 'user-42');
      expect(user?.email, isNull);
    });
  });
}
