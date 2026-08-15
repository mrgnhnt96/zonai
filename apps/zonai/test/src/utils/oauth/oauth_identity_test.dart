import 'package:test/test.dart';
import 'package:zonai_schema/src/types/oauth/oauth_claim_map.dart';

import 'package:zonai/src/utils/oauth/oauth_exception.dart';
import 'package:zonai/src/utils/oauth/oauth_identity.dart';

void main() {
  group(extractOAuthIdentity, () {
    test('extracts a flat claim map (Google-shaped)', () {
      const claims = OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
        picture: 'picture',
      );
      final identity = extractOAuthIdentity(claims, {
        'sub': 'user-1',
        'email': 'a@example.com',
        'email_verified': true,
        'name': 'A User',
        'picture': 'https://example.com/a.png',
      });

      expect(identity.subject, 'user-1');
      expect(identity.email, 'a@example.com');
      expect(identity.emailVerified, isTrue);
      expect(identity.name, 'A User');
      expect(identity.picture, 'https://example.com/a.png');
    });

    test('resolves a dotted claim path (Facebook-shaped picture)', () {
      const claims = OAuthClaimMap(
        subject: 'id',
        email: 'email',
        name: 'name',
        picture: 'picture.data.url',
      );
      final identity = extractOAuthIdentity(claims, {
        'id': 'fb-1',
        'name': 'A User',
        'email': 'a@example.com',
        'picture': {
          'data': {'url': 'https://fb.example/pic.jpg'},
        },
      });

      expect(identity.picture, 'https://fb.example/pic.jpg');
    });

    test('leaves emailVerified null when the claim map has no path for it '
        '(GitHub-shaped, before the /user/emails fallback runs)', () {
      const claims = OAuthClaimMap(subject: 'id', email: 'email', name: 'name');
      final identity = extractOAuthIdentity(claims, {
        'id': 42,
        'email': null,
        'name': 'A User',
      });

      expect(identity.emailVerified, isNull);
    });

    test('coerces a string boolean-verified claim', () {
      const claims = OAuthClaimMap(
        subject: 'id',
        email: 'email',
        emailVerified: 'verified',
      );
      final identity = extractOAuthIdentity(claims, {
        'id': 'u1',
        'email': 'a@example.com',
        'verified': 'true',
      });

      expect(identity.emailVerified, isTrue);
    });

    test('throws OAuthIdentityUnresolvedException when subject does not '
        'resolve', () {
      const claims = OAuthClaimMap(subject: 'sub', email: 'email');
      expect(
        () => extractOAuthIdentity(claims, {'email': 'a@example.com'}),
        throwsA(isA<OAuthIdentityUnresolvedException>()),
      );
    });

    test('coerces a numeric subject to its decimal string form '
        '(GitHub\'s /user "id" is documented as a JSON integer, not a '
        'string)', () {
      const claims = OAuthClaimMap(subject: 'id', email: 'email');
      final identity = extractOAuthIdentity(claims, {
        'id': 42,
        'email': 'a@example.com',
      });

      expect(identity.subject, '42');
    });

    test('throws OAuthIdentityUnresolvedException when subject is neither a '
        'string nor a number', () {
      const claims = OAuthClaimMap(subject: 'id', email: 'email');
      expect(
        () => extractOAuthIdentity(claims, {
          'id': true,
          'email': 'a@example.com',
        }),
        throwsA(isA<OAuthIdentityUnresolvedException>()),
      );
    });

    test('returns null for an unresolvable dotted path', () {
      const claims = OAuthClaimMap(
        subject: 'id',
        email: 'email',
        picture: 'picture.data.url',
      );
      final identity = extractOAuthIdentity(claims, {
        'id': 'u1',
        'email': 'a@example.com',
        'picture': 'not-a-nested-map',
      });

      expect(identity.picture, isNull);
    });
  });
}
