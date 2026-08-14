import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group(SupabaseExternalIdp, () {
    group('issuerFor', () {
      test('derives the project issuer URL', () {
        expect(
          SupabaseExternalIdp.issuerFor('vshgjqqosbcoshzyznfq'),
          'https://vshgjqqosbcoshzyznfq.supabase.co/auth/v1',
        );
      });
    });

    group('jwksUrlFor', () {
      test('derives the JWKS endpoint URL', () {
        expect(
          SupabaseExternalIdp.jwksUrlFor('abc123'),
          'https://abc123.supabase.co/auth/v1/.well-known/jwks.json',
        );
      });
    });

    group('jwks', () {
      test('returns a JwksIdpConfig with derived URLs and the defaults', () {
        final cfg = SupabaseExternalIdp.jwks(
          projectRef: 'abcdef',
          authTable: 'profiles',
        );
        expect(cfg, isA<JwksIdpConfig>());
        expect(cfg.issuer, 'https://abcdef.supabase.co/auth/v1');
        expect(cfg.audience, 'authenticated');
        expect(cfg.authTable, 'profiles');
        expect(
          cfg.jwksUrl,
          'https://abcdef.supabase.co/auth/v1/.well-known/jwks.json',
        );
        expect(cfg.cacheTtl, const Duration(hours: 1));
        expect(cfg.fetchTimeout, const Duration(seconds: 2));
        expect(cfg.adminClaimPath, isNull);
        expect(cfg.adminClaimEquals, isNull);
      });

      test('propagates admin-claim mapping', () {
        final cfg = SupabaseExternalIdp.jwks(
          projectRef: 'abc',
          authTable: 'users',
          adminClaimPath: 'app_metadata.is_admin',
          adminClaimEquals: true,
        );
        expect(cfg.adminClaimPath, 'app_metadata.is_admin');
        expect(cfg.adminClaimEquals, true);
      });

      test('passes through cacheTtl and fetchTimeout', () {
        final cfg = SupabaseExternalIdp.jwks(
          projectRef: 'abc',
          authTable: 'users',
          cacheTtl: const Duration(minutes: 5),
          fetchTimeout: const Duration(seconds: 10),
        );
        expect(cfg.cacheTtl, const Duration(minutes: 5));
        expect(cfg.fetchTimeout, const Duration(seconds: 10));
      });

      test('rejects an empty project ref', () {
        expect(
          () => SupabaseExternalIdp.jwks(projectRef: '', authTable: 'profiles'),
          throwsArgumentError,
        );
      });

      test('rejects a URL passed as projectRef', () {
        expect(
          () => SupabaseExternalIdp.jwks(
            projectRef: 'https://abc.supabase.co',
            authTable: 'profiles',
          ),
          throwsArgumentError,
        );
      });

      test('rejects uppercase or special characters in projectRef', () {
        expect(
          () => SupabaseExternalIdp.jwks(
            projectRef: 'AbcDef',
            authTable: 'profiles',
          ),
          throwsArgumentError,
        );
        expect(
          () => SupabaseExternalIdp.jwks(
            projectRef: 'abc-def',
            authTable: 'profiles',
          ),
          throwsArgumentError,
        );
      });
    });

    group('sharedSecret', () {
      test('returns a SharedSecretIdpConfig with derived issuer', () {
        final cfg = SupabaseExternalIdp.sharedSecret(
          projectRef: 'abc',
          authTable: 'profiles',
          secret: 'top-secret-hmac',
        );
        expect(cfg, isA<SharedSecretIdpConfig>());
        expect(cfg.issuer, 'https://abc.supabase.co/auth/v1');
        expect(cfg.audience, 'authenticated');
        expect(cfg.authTable, 'profiles');
        expect(cfg.secret, 'top-secret-hmac');
      });

      test('rejects an empty project ref', () {
        expect(
          () => SupabaseExternalIdp.sharedSecret(
            projectRef: '',
            authTable: 'profiles',
            secret: 'x',
          ),
          throwsArgumentError,
        );
      });
    });
  });

  group(SupabaseClaims, () {
    group('from', () {
      test('decodes a verified-phone Supabase session', () {
        final claims = SupabaseClaims.from({
          'sub': '9d3a8e98-91f5-41eb-b04b-222eb6720c86',
          'aud': 'authenticated',
          'role': 'authenticated',
          'is_anonymous': false,
          'email': 'user@example.com',
          'phone': '+12025550100',
          'app_metadata': {'provider': 'phone', 'is_admin': false},
          'user_metadata': {'display_name': 'Alex'},
        });
        expect(claims.sub, '9d3a8e98-91f5-41eb-b04b-222eb6720c86');
        expect(claims.isAnonymous, isFalse);
        expect(claims.email, 'user@example.com');
        expect(claims.phone, '+12025550100');
        expect(claims.role, 'authenticated');
        expect(claims.appMetadata, {'provider': 'phone', 'is_admin': false});
        expect(claims.userMetadata, {'display_name': 'Alex'});
      });

      test('normalizes anonymous-session empty-string sentinels to null', () {
        final claims = SupabaseClaims.from({
          'sub': 'sub-anon',
          'aud': 'authenticated',
          'role': 'authenticated',
          'is_anonymous': true,
          'email': '',
          'phone': '',
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
        });
        expect(claims.sub, 'sub-anon');
        expect(claims.isAnonymous, isTrue);
        expect(claims.email, isNull);
        expect(claims.phone, isNull);
        expect(claims.appMetadata, isEmpty);
        expect(claims.userMetadata, isEmpty);
      });

      test('treats missing email / phone the same as empty string', () {
        final claims = SupabaseClaims.from({
          'sub': 'sub',
          'is_anonymous': true,
        });
        expect(claims.email, isNull);
        expect(claims.phone, isNull);
        expect(claims.role, isNull);
        expect(claims.appMetadata, isNull);
        expect(claims.userMetadata, isNull);
      });

      test('coerces app_metadata to Map<String, Object?>', () {
        // JSON decoders surface untyped maps; SupabaseClaims should
        // cast cleanly without the consumer having to.
        final claims = SupabaseClaims.from({
          'sub': 'sub',
          'is_anonymous': false,
          'app_metadata': <dynamic, dynamic>{
            'is_admin': true,
            'provider': 'phone',
          },
        });
        expect(claims.appMetadata, isA<Map<String, Object?>>());
        expect(claims.appMetadata?['is_admin'], true);
      });

      test('rejects missing sub', () {
        expect(
          () => SupabaseClaims.from({'is_anonymous': true}),
          throwsArgumentError,
        );
      });

      test('rejects empty-string sub', () {
        expect(
          () => SupabaseClaims.from({'sub': '', 'is_anonymous': true}),
          throwsArgumentError,
        );
      });

      test('rejects a non-string sub', () {
        expect(
          () => SupabaseClaims.from({'sub': 42, 'is_anonymous': false}),
          throwsArgumentError,
        );
      });

      test('treats non-true is_anonymous as false', () {
        // Supabase always emits a boolean, but defensive normalization
        // avoids surprises if a custom hook injects something else.
        expect(
          SupabaseClaims.from({
            'sub': 'sub',
            'is_anonymous': 'false',
          }).isAnonymous,
          isFalse,
        );
        expect(SupabaseClaims.from({'sub': 'sub'}).isAnonymous, isFalse);
      });

      test('treats malformed metadata maps as null rather than throwing', () {
        // A misconfigured custom-claim hook on the IdP side shouldn't
        // crash the provisioning path — surface as missing instead.
        final claims = SupabaseClaims.from({
          'sub': 'sub',
          'is_anonymous': false,
          'app_metadata': 'not-a-map',
        });
        expect(claims.appMetadata, isNull);
      });
    });
  });
}
