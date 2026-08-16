@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:test/test.dart';
import 'package:zonai/src/exceptions/auth_exception.dart';
import 'package:zonai/src/utils/jwks_idp_verifier.dart';
import 'package:zonai/src/utils/oauth/oauth_provider_credentials.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// [JwksIdpVerifier] against **a real OIDC issuer over the real network**
/// (`docs/oauth.md`, "Live-network JWKS verification").
///
/// `jwks_idp_verifier_test.dart` covers the logic thoroughly — 18 cases — but
/// every one of them generates its own RSA key pair and serves the JWKS from
/// a `MockClient`. That proves the verifier is self-consistent. It cannot
/// prove the verifier works against a key document it did not author, which
/// is the only kind it will ever meet in production.
///
/// ## The specific thing a fake cannot catch
///
/// `_refreshCache` skips key entries `jose` fails to parse:
///
///     try { keyStore.addKey(JsonWebKey.fromJson(raw)); }
///     on Object { continue; }
///
/// That `continue` is right — one broken row should not kill a refresh — but
/// it is silent. If a real issuer published keys in a shape `jose` rejected,
/// every key would be skipped, the store would come back empty, and every
/// sign-in would fail with a bare [InvalidJwtException] indistinguishable
/// from a bad token. A test that authors its own JWKS can never observe
/// this, because it only ever writes shapes `jose` just produced.
///
/// ## Why Google, and why a gcloud token
///
/// `gcloud auth print-identity-token` mints a genuine Google-signed OIDC
/// `id_token`: `iss` is `https://accounts.google.com`, which is exactly the
/// issuer [OAuthProvider.google] declares, signed by a key in exactly the
/// JWKS it declares. Its `aud` is the gcloud CLI's own public client id
/// rather than ours — so the provider below is constructed with that client
/// id. gcloud is a legitimate Google OAuth client; pointing the config at it
/// exercises the real [oauthJwksConfig] wiring rather than a hand-rolled
/// config.
///
/// What that does **not** prove, and this file should keep saying so: nothing
/// here exercises the browser redirect, the consent screen, the code
/// exchange, or `aud` matching *our* client id. It proves the half that the
/// mock authored: fetch, parse, kid lookup, signature, claims.
///
/// ## Credential handling
///
/// The token is a live bearer credential and carries the account's `sub` and
/// email. It is read, never written: not printed, not put in a failure
/// message, not saved. Assertions are on shape.
void main() {
  group('JwksIdpVerifier against live Google JWKS', () {
    String? idToken;
    String? unavailable;

    setUpAll(() async {
      final fromEnv = Platform.environment['GOOGLE_ID_TOKEN'];
      if (fromEnv != null && fromEnv.isNotEmpty) {
        idToken = fromEnv;
        return;
      }

      // Falling back to gcloud keeps the token out of the shell environment
      // and out of history, which is the safer place for a live credential.
      final ProcessResult result;
      try {
        result = await Process.run('gcloud', ['auth', 'print-identity-token']);
      } on ProcessException {
        unavailable =
            'gcloud is not installed and GOOGLE_ID_TOKEN is unset -- this '
            'test needs a real Google-signed id_token and is skipped rather '
            'than faked.';
        markTestSkipped(unavailable!);
        return;
      }

      final out = (result.stdout as String).trim();
      if (result.exitCode != 0 || out.isEmpty) {
        // Deliberately does not echo stderr: gcloud errors can quote account
        // names.
        unavailable =
            'gcloud auth print-identity-token failed (exit '
            '${result.exitCode}) -- run `gcloud auth login` first. Skipped '
            'rather than faked.';
        markTestSkipped(unavailable!);
        return;
      }
      idToken = out;
    });

    /// The `aud`/`iss` of [jwt] without verifying it — used only to build the
    /// config the verifier is then asked to check the token against.
    Map<String, Object?> unverifiedClaims(String jwt) {
      final payload = jwt.split('.')[1];
      final normalized = base64Url.normalize(payload);
      return jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, Object?>;
    }

    /// Collapses a successful [JwksIdpVerifier.verify] into a fixed marker
    /// string.
    ///
    /// The negative tests below assert that verify() *throws*. Handed the
    /// future directly, `expectLater` prints the actual value when the
    /// expectation fails — and the actual value is the decoded claim map,
    /// which carries the account's real `sub` and email. A control run with
    /// the signature check disabled printed exactly that. Mapping success to
    /// a constant means a regression in these tests reports "it verified"
    /// instead of dumping the credential into the output.
    Future<String> outcomeOf(Future<Map<String, Object?>> verification) async {
      await verification;
      return 'verify() returned claims (redacted) instead of throwing';
    }

    /// A real [JwksIdpConfig] for Google, built through the production helper
    /// rather than by hand. [audience] defaults to the token's own `aud`.
    JwksIdpConfig configFor(String audience) {
      final provider = OAuthProvider.google(
        clientId: audience,
        // Never sent: verification only fetches the public JWKS. Present
        // because the factory requires a non-empty value.
        clientSecret: 'unused-for-verification',
      );
      final config = oauthJwksConfig(provider);
      // Google declares both `issuer` and `jwks`, so this is non-null. If it
      // ever became null the tests below would fail on a null check with no
      // explanation, hence the assertion here.
      expect(
        config,
        isNotNull,
        reason: 'OAuthProvider.google declares issuer and jwks endpoints',
      );
      return config!;
    }

    test('verifies a genuine Google-signed id_token end to end', () async {
      final token = idToken;
      if (token == null) return;

      final claims = unverifiedClaims(token);
      final audience = claims['aud']! as String;

      final verifier = JwksIdpVerifier(configFor(audience));
      addTearDown(verifier.dispose);

      // Everything real: an https fetch of Google's live JWKS, `jose`
      // parsing keys Google published, a kid lookup against them, and an
      // RS256 signature Google produced.
      final verified = await verifier.verify(token);

      expect(verified['iss'], 'https://accounts.google.com');
      expect(verified['aud'], audience);
      expect(verified['sub'], isA<String>());
      expect(verified['sub'], isNotEmpty);
      // `exp` is validated inside verify(); asserting it is present and
      // numeric confirms the claim survived decoding rather than that the
      // check ran.
      expect(verified['exp'], isA<num>());
    });

    test('every key in Google\'s live JWKS parses -- the silent `continue` '
        'in _refreshCache skips nothing here', () async {
      final client = http.Client();
      addTearDown(client.close);

      final response = await client.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/certs'),
      );
      expect(response.statusCode, 200);

      final keys =
          (jsonDecode(response.body) as Map<String, dynamic>)['keys'] as List;
      expect(
        keys,
        isNotEmpty,
        reason: 'Google always publishes at least one signing key',
      );

      // Mirrors _refreshCache's loop with the `continue` removed: a throw
      // here is a key the production path would have silently dropped.
      for (final raw in keys) {
        expect(
          raw,
          isA<Map<String, dynamic>>(),
          reason: 'a non-map entry is skipped silently by _refreshCache',
        );
        expect(
          () => JsonWebKey.fromJson(raw as Map<String, dynamic>),
          returnsNormally,
          reason:
              'jose cannot parse a key Google publishes -- _refreshCache '
              'would skip it silently and sign-ins would fail with a bare '
              'InvalidJwtException',
        );
      }
    });

    test('rejects a real token when the audience does not match', () async {
      final token = idToken;
      if (token == null) return;

      // Without this, the passing test above would also pass if the `aud`
      // check were removed entirely.
      final verifier = JwksIdpVerifier(
        configFor('not-the-audience.apps.googleusercontent.com'),
      );
      addTearDown(verifier.dispose);

      await expectLater(
        outcomeOf(verifier.verify(token)),
        throwsA(isA<InvalidJwtException>()),
      );
    });

    test('rejects a real token whose signature has been altered', () async {
      final token = idToken;
      if (token == null) return;

      final claims = unverifiedClaims(token);
      final verifier = JwksIdpVerifier(configFor(claims['aud']! as String));
      addTearDown(verifier.dispose);

      // Flip one character of the signature, leaving the header and payload
      // byte-identical. The only thing that can reject this is a real
      // signature check against a key really fetched from Google -- which is
      // the assertion the passing test cannot make on its own.
      final parts = token.split('.');
      final signature = parts[2];
      final flipped = signature[0] == 'A' ? 'B' : 'A';
      final tampered =
          '${parts[0]}.${parts[1]}.$flipped${signature.substring(1)}';

      await expectLater(
        outcomeOf(verifier.verify(tampered)),
        throwsA(isA<InvalidJwtException>()),
      );
    });
  });
}
