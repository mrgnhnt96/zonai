import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

const _strongJwt = 'CqW3nZ8tRv6yLpJ2xHsB5dKm9GfTbNc4';
const _strongPassword = 'Ye7VmQ4rXz2wKtDh6NsLp9JbGc3FvRa8';

/// RFC 8291's application-server key pair — a real P-256 pair.
const _publicKey =
    'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8';
const _privateKey = 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw';

const _webPush = WebPushConfig(
  publicKey: _publicKey,
  privateKey: WebPushPrivateKey.inline(_privateKey),
  subject: 'mailto:ops@example.com',
);

AppConfig _withPush(PushConfig push) => AppConfig(
  appName: 'Web',
  jwtSecret: _strongJwt,
  passwordSecret: _strongPassword,
  push: push,
);

Matcher _refusal(String fragment) => throwsA(
  isA<StateError>().having((e) => e.message, 'message', contains(fragment)),
);

void main() {
  group('DevicePlatform.web', () {
    test('is stored as web', () {
      expect(DevicePlatform.web.toJson(), 'web');
    });

    test('accepts the spellings client code writes for a browser', () {
      for (final value in [
        'web',
        'WEB',
        ' web ',
        'webpush',
        'web-push',
        'web_push',
        'browser',
      ]) {
        expect(
          DevicePlatform.tryParse(value),
          DevicePlatform.web,
          reason: value,
        );
      }
    });
  });

  group('PushConfig.webPush', () {
    test('round-trips through json, inline and file', () {
      for (final key in const [
        WebPushPrivateKey.inline(_privateKey),
        WebPushPrivateKey.file('/run/secrets/vapid.pem'),
      ]) {
        final config = PushConfig(
          webPush: WebPushConfig(
            publicKey: _publicKey,
            privateKey: key,
            subject: 'https://example.com',
          ),
        );

        final back = PushConfig.fromJson(config.toJson());

        expect(back.hasWebPush, isTrue);
        expect(back.webPush!.publicKey, _publicKey);
        expect(back.webPush!.privateKey, key);
        expect(back.webPush!.subject, 'https://example.com');
      }
    });

    test('is absent unless configured, and survives withApns', () {
      expect(const PushConfig().hasWebPush, isFalse);
      expect(const PushConfig().toJson().containsKey('webPush'), isFalse);

      const apns = ApnsConfig(
        credentials: ApnsCredentials.inline('pem'),
        keyId: 'K',
        teamId: 'T',
        bundleId: 'b',
      );
      expect(
        const PushConfig(webPush: _webPush).withApns(apns).webPush,
        same(_webPush),
      );
    });
  });

  group('AppConfig.validate with webPush', () {
    test('a web-only push config is a complete one', () {
      _withPush(const PushConfig(webPush: _webPush)).validate();
    });

    test('accepts a PEM private key without decoding it', () {
      _withPush(
        const PushConfig(
          webPush: WebPushConfig(
            publicKey: _publicKey,
            privateKey: WebPushPrivateKey.inline(
              '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----',
            ),
            subject: 'mailto:ops@example.com',
          ),
        ),
      ).validate();
    });

    test('refuses a public key that is not an uncompressed point', () {
      expect(
        () => _withPush(
          const PushConfig(
            webPush: WebPushConfig(
              publicKey: 'BTBZMqHH6r4Tts7J_aSIgg',
              privateKey: WebPushPrivateKey.inline(_privateKey),
              subject: 'mailto:ops@example.com',
            ),
          ),
        ).validate(),
        _refusal('push.webPush.publicKey'),
      );
    });

    test('refuses an empty or malformed private key', () {
      for (final key in const ['', 'not-a-key']) {
        expect(
          () => _withPush(
            PushConfig(
              webPush: WebPushConfig(
                publicKey: _publicKey,
                privateKey: WebPushPrivateKey.inline(key),
                subject: 'mailto:ops@example.com',
              ),
            ),
          ).validate(),
          _refusal('push.webPush.privateKey'),
          reason: key,
        );
      }
    });

    test('refuses a subject that is neither mailto: nor https:', () {
      for (final subject in const ['', 'ops@example.com', 'http://x.test']) {
        expect(
          () => _withPush(
            PushConfig(
              webPush: WebPushConfig(
                publicKey: _publicKey,
                privateKey: const WebPushPrivateKey.inline(_privateKey),
                subject: subject,
              ),
            ),
          ).validate(),
          _refusal('push.webPush.subject'),
          reason: subject,
        );
      }
    });

    test('push with no transport at all names Web Push as an option', () {
      expect(
        () => _withPush(const PushConfig()).validate(),
        _refusal('Web Push (webPush)'),
      );
    });
  });
}
