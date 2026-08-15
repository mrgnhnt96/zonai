import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jose/jose.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';

import 'package:zonai/src/exceptions/auth_exception.dart';
import 'package:zonai/src/utils/jwks_idp_verifier.dart';
import 'package:zonai/src/utils/oauth/oauth_id_token_verifier.dart';
import 'package:zonai/src/utils/oauth/oauth_provider_credentials.dart';

({JsonWebKey signingKey, Map<String, dynamic> publicJwk}) _makeKeyPair({
  String kid = 'kid-1',
}) {
  final signing = JsonWebKey.generate('RS256');
  final publicSet = JsonWebKeySet.fromJson({
    'keys': [signing.toJson()],
  }).toJson();
  final publicJwk = Map<String, dynamic>.from(
    (publicSet['keys'] as List).first as Map,
  )..['kid'] = kid;
  publicJwk.removeWhere(
    (k, _) => const {'d', 'p', 'q', 'dp', 'dq', 'qi'}.contains(k),
  );
  final signingWithKid = JsonWebKey.fromJson({...signing.toJson(), 'kid': kid});
  return (signingKey: signingWithKid, publicJwk: publicJwk);
}

Future<String> _signIdToken(
  JsonWebKey signingKey,
  Map<String, Object?> payload,
) async {
  final builder = JsonWebSignatureBuilder()
    ..jsonContent = payload
    ..addRecipient(signingKey, algorithm: 'RS256');
  return builder.build().toCompactSerialization();
}

void main() {
  group(verifyOAuthIdToken, () {
    final now = DateTime.utc(2026, 6, 1, 12);
    final nowSecs = now.millisecondsSinceEpoch ~/ 1000;
    final provider = OAuthProvider.google(clientId: 'cid', clientSecret: 's');

    JwksIdpVerifier verifierWith(Map<String, dynamic> publicJwk) {
      final config = oauthJwksConfig(provider)!;
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keys': [publicJwk],
          }),
          200,
        ),
      );
      return JwksIdpVerifier(config, httpClient: mockClient);
    }

    Map<String, Object?> validPayload({
      String? iss,
      Object? aud,
      int? exp,
      String? nonce,
    }) => {
      'iss': iss ?? provider.endpoints.issuer,
      'aud': aud ?? oauthClientId(provider),
      'exp': exp ?? nowSecs + 300,
      'sub': 'user-1',
      'nonce': nonce ?? 'expected-nonce',
    };

    test('verifies a valid id_token and returns its claims', () async {
      final pair = _makeKeyPair();
      final verifier = verifierWith(pair.publicJwk);
      final token = await _signIdToken(pair.signingKey, validPayload());

      await withClock(Clock.fixed(now), () async {
        final claims = await verifyOAuthIdToken(
          verifier: verifier,
          idToken: token,
          expectedNonce: 'expected-nonce',
        );
        expect(claims['sub'], 'user-1');
      });
    });

    test('rejects a token whose nonce does not match', () async {
      final pair = _makeKeyPair();
      final verifier = verifierWith(pair.publicJwk);
      final token = await _signIdToken(
        pair.signingKey,
        validPayload(nonce: 'attacker-supplied-nonce'),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifyOAuthIdToken(
            verifier: verifier,
            idToken: token,
            expectedNonce: 'expected-nonce',
          ),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects a token whose aud does not match the client_id', () async {
      final pair = _makeKeyPair();
      final verifier = verifierWith(pair.publicJwk);
      final token = await _signIdToken(
        pair.signingKey,
        validPayload(aud: 'someone-elses-client-id'),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifyOAuthIdToken(
            verifier: verifier,
            idToken: token,
            expectedNonce: 'expected-nonce',
          ),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test(
      'rejects a token whose iss does not match the provider issuer',
      () async {
        final pair = _makeKeyPair();
        final verifier = verifierWith(pair.publicJwk);
        final token = await _signIdToken(
          pair.signingKey,
          validPayload(iss: 'https://attacker.example'),
        );

        await withClock(Clock.fixed(now), () async {
          await expectLater(
            verifyOAuthIdToken(
              verifier: verifier,
              idToken: token,
              expectedNonce: 'expected-nonce',
            ),
            throwsA(isA<InvalidJwtException>()),
          );
        });
      },
    );

    test('rejects an expired token', () async {
      final pair = _makeKeyPair();
      final verifier = verifierWith(pair.publicJwk);
      final token = await _signIdToken(
        pair.signingKey,
        validPayload(exp: nowSecs - 60),
      );

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifyOAuthIdToken(
            verifier: verifier,
            idToken: token,
            expectedNonce: 'expected-nonce',
          ),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('rejects a malformed id_token', () async {
      final pair = _makeKeyPair();
      final verifier = verifierWith(pair.publicJwk);

      await withClock(Clock.fixed(now), () async {
        await expectLater(
          verifyOAuthIdToken(
            verifier: verifier,
            idToken: 'not-a-jwt',
            expectedNonce: 'expected-nonce',
          ),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });
  });

  group(oauthJwksConfig, () {
    test('builds a config for a verifiable OIDC provider (Google)', () {
      final provider = OAuthProvider.google(clientId: 'cid', clientSecret: 's');
      final config = oauthJwksConfig(provider);
      expect(config, isNotNull);
      expect(config!.issuer, 'https://accounts.google.com');
      expect(config.audience, 'cid');
      expect(config.jwksUrl, 'https://www.googleapis.com/oauth2/v3/certs');
    });

    test('returns null for a provider with no issuer/jwks (GitHub)', () {
      final provider = OAuthProvider.github(clientId: 'cid', clientSecret: 's');
      expect(oauthJwksConfig(provider), isNull);
    });
  });
}
