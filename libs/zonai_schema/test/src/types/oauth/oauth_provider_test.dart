import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Fails if [secret] shows up anywhere in [provider]'s redacted payload —
/// asserted against the serialized map rather than a fixed field list, so a
/// field added later that accidentally carries a secret is still caught.
void _expectRedacted(OAuthProvider provider, String secret, {String? why}) {
  final json = provider.toPublic(table: 'users').toJson();
  expect(
    jsonEncode(json),
    isNot(contains(secret)),
    reason: why ?? 'toPublic() leaked "$secret"',
  );
}

void main() {
  group('OAuthProvider.google', () {
    test('bakes in the documented OIDC endpoints, scopes and claims', () {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      expect(provider.id, 'google');
      expect(provider.displayName, 'Google');
      expect(
        provider.endpoints.authorization,
        'https://accounts.google.com/o/oauth2/v2/auth',
      );
      expect(provider.endpoints.token, 'https://oauth2.googleapis.com/token');
      expect(
        provider.endpoints.userInfo,
        'https://openidconnect.googleapis.com/v1/userinfo',
      );
      expect(provider.endpoints.issuer, 'https://accounts.google.com');
      expect(
        provider.endpoints.jwks,
        'https://www.googleapis.com/oauth2/v3/certs',
      );
      expect(provider.scopes, ['openid', 'email', 'profile']);
      expect(provider.claims.subject, 'sub');
      expect(provider.claims.email, 'email');
      expect(provider.claims.emailVerified, 'email_verified');
      expect(provider.usesPkce, isTrue);
      expect(provider.linking, OAuthLinking.byVerifiedEmail);
      expect(provider, isA<BuiltInOAuthProvider>());
      expect(provider.kind, OAuthProviderKind.google);
    });

    test('scopes and linking are overridable', () {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'secret',
        scopes: const ['openid', 'email'],
        linking: OAuthLinking.never,
      );

      expect(provider.scopes, ['openid', 'email']);
      expect(provider.linking, OAuthLinking.never);
    });

    test('rejects an empty clientId', () {
      expect(
        () => OAuthProvider.google(clientId: '', clientSecret: 'secret'),
        throwsArgumentError,
      );
    });

    test('rejects an empty clientSecret', () {
      expect(
        () => OAuthProvider.google(clientId: 'cid', clientSecret: ''),
        throwsArgumentError,
      );
    });
  });

  group('OAuthProvider.apple', () {
    late BuiltInOAuthProvider provider;

    setUp(() {
      provider = OAuthProvider.apple(
        clientId: 'com.example.app',
        teamId: 'team-1',
        keyId: 'key-1',
        privateKey: '-----BEGIN PRIVATE KEY-----',
      );
    });

    test('has no static client secret and no userinfo endpoint', () {
      expect(provider.clientSecret, isNull);
      expect(provider.endpoints.userInfo, isNull);
      expect(provider.endpoints.issuer, 'https://appleid.apple.com');
      expect(provider.endpoints.jwks, 'https://appleid.apple.com/auth/keys');
      expect(provider.scopes, ['name', 'email']);
      expect(provider.claims.subject, 'sub');
      expect(provider.claims.name, isNull);
    });

    test('requires teamId, keyId and privateKey', () {
      expect(
        () => OAuthProvider.apple(
          clientId: 'com.example.app',
          teamId: '',
          keyId: 'key-1',
          privateKey: 'pk',
        ),
        throwsArgumentError,
      );
      expect(
        () => OAuthProvider.apple(
          clientId: 'com.example.app',
          teamId: 'team-1',
          keyId: '',
          privateKey: 'pk',
        ),
        throwsArgumentError,
      );
      expect(
        () => OAuthProvider.apple(
          clientId: 'com.example.app',
          teamId: 'team-1',
          keyId: 'key-1',
          privateKey: '',
        ),
        throwsArgumentError,
      );
    });

    test('toPublic() leaks neither the private key nor its identifiers', () {
      _expectRedacted(provider, '-----BEGIN PRIVATE KEY-----');
      _expectRedacted(provider, 'team-1');
      _expectRedacted(provider, 'key-1');
    });
  });

  group('OAuthProvider.github', () {
    test('is not OIDC and reads email from /user', () {
      final provider = OAuthProvider.github(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      expect(provider.endpoints.issuer, isNull);
      expect(provider.endpoints.jwks, isNull);
      expect(provider.endpoints.userInfo, 'https://api.github.com/user');
      expect(provider.scopes, ['read:user', 'user:email']);
      expect(provider.claims.subject, 'id');
      expect(provider.claims.picture, 'avatar_url');
    });
  });

  group('OAuthProvider.microsoft', () {
    test(
      'defaults to the common multi-tenant endpoint with no fixed issuer',
      () {
        final provider = OAuthProvider.microsoft(
          clientId: 'cid',
          clientSecret: 'secret',
        );

        expect(
          provider.endpoints.authorization,
          'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
        );
        expect(provider.endpoints.issuer, isNull);
      },
    );

    test('a specific tenant resolves a concrete issuer', () {
      final provider = OAuthProvider.microsoft(
        clientId: 'cid',
        clientSecret: 'secret',
        tenant: 'contoso.onmicrosoft.com',
      );

      expect(
        provider.endpoints.authorization,
        'https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/authorize',
      );
      expect(
        provider.endpoints.issuer,
        'https://login.microsoftonline.com/contoso.onmicrosoft.com/v2.0',
      );
    });
  });

  group('OAuthProvider.facebook', () {
    test('reads a nested picture claim path', () {
      final provider = OAuthProvider.facebook(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      expect(provider.claims.picture, 'picture.data.url');
      expect(provider.claims.subject, 'id');
    });
  });

  group('OAuthProvider.discord', () {
    test('reads the verified flag and username', () {
      final provider = OAuthProvider.discord(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      expect(provider.claims.emailVerified, 'verified');
      expect(provider.claims.name, 'username');
      expect(provider.endpoints.userInfo, 'https://discord.com/api/users/@me');
    });
  });

  group('OAuthProvider.gitlab', () {
    test('is a standard OIDC provider', () {
      final provider = OAuthProvider.gitlab(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      expect(provider.endpoints.issuer, 'https://gitlab.com');
      expect(provider.scopes, ['openid', 'email', 'profile']);
    });
  });

  group('OAuthProvider.linkedin', () {
    test('is a standard OIDC provider', () {
      final provider = OAuthProvider.linkedin(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      expect(
        provider.endpoints.userInfo,
        'https://api.linkedin.com/v2/userinfo',
      );
      expect(provider.scopes, ['openid', 'profile', 'email']);
    });
  });

  group('OAuthProvider.custom', () {
    OAuthProvider build({
      String id = 'acme',
      String clientId = 'cid',
      String clientSecret = 'secret',
    }) {
      return OAuthProvider.custom(
        id: id,
        displayName: 'Acme SSO',
        endpoints: const OAuthEndpoints(
          authorization: 'https://sso.acme.com/authorize',
          token: 'https://sso.acme.com/token',
          userInfo: 'https://sso.acme.com/userinfo',
          issuer: 'https://sso.acme.com',
          jwks: 'https://sso.acme.com/.well-known/jwks.json',
        ),
        scopes: const ['openid', 'email', 'profile'],
        claims: const OAuthClaimMap(subject: 'sub', email: 'email'),
        clientId: clientId,
        clientSecret: clientSecret,
      );
    }

    test('expresses an arbitrary OIDC provider', () {
      final provider = build();

      expect(provider, isA<CustomOAuthProvider>());
      expect(provider.id, 'acme');
      expect(provider.endpoints.token, 'https://sso.acme.com/token');
      expect(provider.usesPkce, isTrue);
      expect(provider.linking, OAuthLinking.byVerifiedEmail);
    });

    test('rejects an empty id', () {
      expect(() => build(id: ''), throwsArgumentError);
    });

    test('rejects an empty clientId', () {
      expect(() => build(clientId: ''), throwsArgumentError);
    });

    test('rejects an empty clientSecret', () {
      expect(() => build(clientSecret: ''), throwsArgumentError);
    });

    test('toPublic() carries no secret', () {
      final provider = build(clientSecret: 'super-secret-value');
      _expectRedacted(provider, 'super-secret-value');
    });
  });

  group('OAuthProvider.toPublic', () {
    test('never leaks the client secret or the token/userinfo endpoints', () {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'ultra-secret',
      );

      _expectRedacted(provider, 'ultra-secret');
      _expectRedacted(provider, provider.endpoints.token);
      _expectRedacted(provider, provider.endpoints.userInfo!);
    });

    test('carries exactly the documented public fields', () {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      final public = provider.toPublic(table: 'users');

      expect(public.id, 'google');
      expect(public.displayName, 'Google');
      expect(public.table, 'users');
      expect(public.kind, OAuthProviderKind.google);
      expect(public.startPath, '/auth/oauth/start/google?table=users');
      expect(public.iconUrl, isNull);
      expect(public.iconSvg, isNull);
    });

    test('a custom provider reports OAuthProviderKind.custom', () {
      final provider = OAuthProvider.custom(
        id: 'acme',
        displayName: 'Acme SSO',
        endpoints: const OAuthEndpoints(
          authorization: 'https://sso.acme.com/authorize',
          token: 'https://sso.acme.com/token',
        ),
        scopes: const ['openid'],
        claims: const OAuthClaimMap(subject: 'sub', email: 'email'),
        clientId: 'cid',
        clientSecret: 'secret',
        brand: const OAuthBrand(
          icon: OAuthIcon.url('https://acme.example/icon.svg'),
        ),
      );

      final public = provider.toPublic(table: 'users');
      expect(public.kind, OAuthProviderKind.custom);
      expect(public.iconUrl, 'https://acme.example/icon.svg');
      expect(public.iconSvg, isNull);
    });
  });
}
