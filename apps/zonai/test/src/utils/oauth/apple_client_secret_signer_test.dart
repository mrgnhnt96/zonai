import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:jose/jose.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';

import 'package:zonai/src/utils/oauth/apple_client_secret_signer.dart';
import 'package:zonai/src/utils/oauth/oauth_exception.dart';

// A real P-256 PKCS8 key, generated once via:
//   openssl ecparam -genkey -name prime256v1 -noout | openssl pkcs8 -topk8 -nocrypt
// Exactly the format Apple's `.p8` download is. Committed here as a fixed,
// known-answer key so tests are deterministic — never a real Apple key.
const _testPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgFbgeH0A1XSR6v1QR
JnZFXZx0grlUHDXyjtG0/3WrqtWhRANCAAQXcjok5AXJsDSs0JnEZqAVvTp2wl1Z
B4cAe3piuRoFVz26mIS3EAQNUKkU5eEnggM3go9IX8fRu5Y8pkHg0O7L
-----END PRIVATE KEY-----
''';

const _testPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEF3I6JOQFybA0rNCZxGagFb06dsJd
WQeHAHt6YrkaBVc9upiEtxAEDVCpFOXhJ4IDN4KPSF/H0buWPKZB4NDuyw==
-----END PUBLIC KEY-----
''';

BuiltInOAuthProvider _appleProvider({
  String teamId = 'TESTTEAM123',
  String keyId = 'TESTKID456',
  String clientId = 'com.example.app',
  String privateKey = _testPrivateKeyPem,
}) => OAuthProvider.apple(
  clientId: clientId,
  teamId: teamId,
  keyId: keyId,
  privateKey: privateKey,
);

Map<String, Object?> _decodeSegment(String segment) {
  var padded = segment;
  final mod = padded.length % 4;
  if (mod != 0) padded += '=' * (4 - mod);
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, Object?>;
}

Future<bool> _verifiesAgainstPublicKey(
  String compactJwt, {
  required String kid,
}) async {
  final jws = JsonWebSignature.fromCompactSerialization(compactJwt);
  // The store selects a key by matching the JWS header's `kid` against the
  // key's own `kid` — a keyId-less key can't be matched even though it's
  // cryptographically the right one, so this must carry the same kid the
  // signer put in the header.
  final keyStore = JsonWebKeyStore()
    ..addKey(JsonWebKey.fromPem(_testPublicKeyPem, keyId: kid));
  return jws.verify(keyStore);
}

void main() {
  group(AppleClientSecretSigner, () {
    final now = DateTime.utc(2026, 3, 1, 12);
    final nowSecs = now.millisecondsSinceEpoch ~/ 1000;

    test('signs an ES256 JWT with the documented claim shape, against a known '
        'key and fixed clock', () async {
      final signer = AppleClientSecretSigner(
        expiresIn: const Duration(days: 150),
      );
      final provider = _appleProvider();

      final jwt = await withClock(
        Clock.fixed(now),
        () async => signer.sign(provider),
      );

      final parts = jwt.split('.');
      expect(parts, hasLength(3));

      final header = _decodeSegment(parts[0]);
      expect(header['alg'], 'ES256');
      expect(header['kid'], 'TESTKID456');

      final payload = _decodeSegment(parts[1]);
      expect(payload['iss'], 'TESTTEAM123');
      expect(payload['sub'], 'com.example.app');
      expect(payload['aud'], 'https://appleid.apple.com');
      expect(payload['iat'], nowSecs);
      expect(
        payload['exp'],
        now.add(const Duration(days: 150)).millisecondsSinceEpoch ~/ 1000,
      );

      expect(await _verifiesAgainstPublicKey(jwt, kid: 'TESTKID456'), isTrue);
    });

    test('rejects an expiresIn beyond Apple\'s 6-month ceiling', () {
      expect(
        () => AppleClientSecretSigner(expiresIn: const Duration(days: 200)),
        throwsArgumentError,
      );
    });

    test(
      'rejects signing a non-Apple provider',
      () => expect(
        () => AppleClientSecretSigner().sign(
          OAuthProvider.google(clientId: 'cid', clientSecret: 'secret'),
        ),
        throwsArgumentError,
      ),
    );

    test('caches the signed JWT: repeated calls at the same instant return the '
        'identical string', () async {
      final signer = AppleClientSecretSigner();
      final provider = _appleProvider();

      await withClock(Clock.fixed(now), () async {
        final first = signer.sign(provider);
        final second = signer.sign(provider);
        expect(second, first);
      });
    });

    test('signs a fresh JWT once the cached one is within the refresh margin '
        'of expiry', () async {
      final signer = AppleClientSecretSigner(
        expiresIn: const Duration(days: 150),
      );
      final provider = _appleProvider();

      final first = await withClock(
        Clock.fixed(now),
        () async => signer.sign(provider),
      );

      // Just inside the 10-minute refresh margin before expiry.
      final nearExpiry = now.add(
        const Duration(days: 150) - const Duration(minutes: 5),
      );
      final second = await withClock(
        Clock.fixed(nearExpiry),
        () async => signer.sign(provider),
      );

      expect(second, isNot(first));
      final payload = _decodeSegment(second.split('.')[1]);
      expect(payload['iat'], nearExpiry.millisecondsSinceEpoch ~/ 1000);
    });

    test('throws OAuthAppleSigningException for a malformed private key', () {
      final provider = _appleProvider(privateKey: 'not a pem key');
      expect(
        () => AppleClientSecretSigner().sign(provider),
        throwsA(isA<OAuthAppleSigningException>()),
      );
    });
  });
}
