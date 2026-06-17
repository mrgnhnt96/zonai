import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/src/config/external_idp_config.dart';

void main() {
  void expectRoundTrip(ExternalIdpConfig config) {
    final json = config.toJson();
    final restored = ExternalIdpConfig.fromJson(json);
    expect(restored.toJson(), json);
    expect(restored.runtimeType, config.runtimeType);
  }

  group(ExternalIdpConfig, () {
    test('SharedSecretIdpConfig round-trips', () {
      expectRoundTrip(
        const SharedSecretIdpConfig(
          issuer: 'https://supabase.example/auth/v1',
          audience: 'authenticated',
          authTable: 'users',
          secret: 'super-secret',
        ),
      );
    });

    test('JwksIdpConfig round-trips with defaults', () {
      expectRoundTrip(
        const JwksIdpConfig(
          issuer: 'https://example.auth0.com/',
          audience: 'api.example.com',
          authTable: 'users',
          jwksUrl: 'https://example.auth0.com/.well-known/jwks.json',
        ),
      );
    });

    test('JwksIdpConfig round-trips with explicit cacheTtl + fetchTimeout', () {
      expectRoundTrip(
        const JwksIdpConfig(
          issuer: 'https://example.auth0.com/',
          audience: 'api.example.com',
          authTable: 'admins',
          jwksUrl: 'https://example.auth0.com/.well-known/jwks.json',
          cacheTtl: Duration(minutes: 15),
          fetchTimeout: Duration(seconds: 5),
        ),
      );
    });

    test('survives jsonEncode/jsonDecode', () {
      final configs = <ExternalIdpConfig>[
        const SharedSecretIdpConfig(
          issuer: 'https://supabase.example/auth/v1',
          audience: 'authenticated',
          authTable: 'users',
          secret: 'super-secret',
        ),
        const JwksIdpConfig(
          issuer: 'https://example.auth0.com/',
          audience: 'api.example.com',
          authTable: 'users',
          jwksUrl: 'https://example.auth0.com/.well-known/jwks.json',
        ),
      ];
      for (final config in configs) {
        final encoded = jsonEncode(config.toJson());
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        final restored = ExternalIdpConfig.fromJson(decoded);
        expect(restored.toJson(), config.toJson());
      }
    });

    test('fromJson throws ArgumentError on unknown type', () {
      expect(
        () => ExternalIdpConfig.fromJson(<String, dynamic>{
          'type': 'mystery_protocol',
          'issuer': 'x',
          'audience': 'y',
          'authTable': 'z',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('JwksIdpConfig defaults match documented values', () {
      const config = JwksIdpConfig(
        issuer: 'https://example.com',
        audience: 'aud',
        authTable: 'users',
        jwksUrl: 'https://example.com/jwks',
      );
      expect(config.cacheTtl, const Duration(hours: 1));
      expect(config.fetchTimeout, const Duration(seconds: 2));
    });

    test('type discriminator is stable per variant', () {
      const shared = SharedSecretIdpConfig(
        issuer: 'a',
        audience: 'b',
        authTable: 'c',
        secret: 'd',
      );
      const jwks = JwksIdpConfig(
        issuer: 'a',
        audience: 'b',
        authTable: 'c',
        jwksUrl: 'd',
      );
      expect(shared.type, 'shared_secret');
      expect(jwks.type, 'jwks');
      expect(shared.toJson()['type'], 'shared_secret');
      expect(jwks.toJson()['type'], 'jwks');
    });

    test('adminClaim fields default to null and are absent from toJson', () {
      const shared = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
      );
      expect(shared.adminClaimPath, isNull);
      expect(shared.adminClaimEquals, isNull);
      final json = shared.toJson();
      expect(json.containsKey('adminClaimPath'), isFalse);
      expect(json.containsKey('adminClaimEquals'), isFalse);
    });

    test('SharedSecretIdpConfig round-trips with adminClaim fields', () {
      expectRoundTrip(
        const SharedSecretIdpConfig(
          issuer: 'https://supabase.example/auth/v1',
          audience: 'authenticated',
          authTable: 'users',
          secret: 'super-secret',
          adminClaimPath: 'app_metadata.is_admin',
          adminClaimEquals: true,
        ),
      );
    });

    test('JwksIdpConfig round-trips with adminClaim fields', () {
      expectRoundTrip(
        const JwksIdpConfig(
          issuer: 'https://example.auth0.com/',
          audience: 'api.example.com',
          authTable: 'users',
          jwksUrl: 'https://example.auth0.com/.well-known/jwks.json',
          adminClaimPath: 'role',
          adminClaimEquals: 'admin',
        ),
      );
    });
  });

  group('resolveAdminFromClaims', () {
    test('returns false when adminClaimPath is null', () {
      const config = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
      );
      expect(resolveAdminFromClaims(config, {'role': 'admin'}), isFalse);
    });

    test('returns true when single-segment claim equals configured value', () {
      const config = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
        adminClaimPath: 'role',
        adminClaimEquals: 'admin',
      );
      expect(
        resolveAdminFromClaims(config, {'role': 'admin', 'sub': 'u1'}),
        isTrue,
      );
    });

    test('returns false when single-segment claim is a different value', () {
      const config = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
        adminClaimPath: 'role',
        adminClaimEquals: 'admin',
      );
      expect(resolveAdminFromClaims(config, {'role': 'user'}), isFalse);
    });

    test('walks nested claims via dotted path (Supabase shape)', () {
      const config = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
        adminClaimPath: 'app_metadata.is_admin',
        adminClaimEquals: true,
      );
      expect(
        resolveAdminFromClaims(config, <String, Object?>{
          'app_metadata': <String, Object?>{'is_admin': true},
        }),
        isTrue,
      );
    });

    test('returns false when nested path resolves to a different value', () {
      const config = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
        adminClaimPath: 'app_metadata.is_admin',
        adminClaimEquals: true,
      );
      expect(
        resolveAdminFromClaims(config, <String, Object?>{
          'app_metadata': <String, Object?>{'is_admin': false},
        }),
        isFalse,
      );
    });

    test('returns false when path traverses through a non-map value', () {
      const config = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
        adminClaimPath: 'app_metadata.is_admin',
        adminClaimEquals: true,
      );
      expect(
        resolveAdminFromClaims(config, <String, Object?>{
          'app_metadata': 'not-a-map',
        }),
        isFalse,
      );
    });

    test('returns false when leaf segment is missing', () {
      const config = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
        adminClaimPath: 'role',
        adminClaimEquals: 'admin',
      );
      expect(resolveAdminFromClaims(config, const {}), isFalse);
    });

    test('matches numeric equality', () {
      const config = SharedSecretIdpConfig(
        issuer: 'i',
        audience: 'a',
        authTable: 't',
        secret: 's',
        adminClaimPath: 'level',
        adminClaimEquals: 10,
      );
      expect(resolveAdminFromClaims(config, {'level': 10}), isTrue);
      expect(resolveAdminFromClaims(config, {'level': 5}), isFalse);
    });
  });
}
