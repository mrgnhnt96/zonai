import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/webhooks/webhook_signature.dart';

void main() {
  // The vector Svix's own libraries test against. The key is kept apart from
  // its whsec_ prefix so secret scanners don't take it for a Stripe secret.
  const rawKey = 'MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw';
  const secret = 'whsec_$rawKey';
  const id = 'msg_p5jXN8AQM9LWM0D4loKWxJek';
  const timestamp = '1614265330';
  const signature = 'v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=';
  final body = utf8.encode('{"test": 2432232314}');
  final sentAt = DateTime.fromMillisecondsSinceEpoch(1614265330 * 1000);

  Map<String, String> headers({
    String prefix = 'svix',
    String sig = signature,
    String ts = timestamp,
  }) => {'$prefix-id': id, '$prefix-timestamp': ts, '$prefix-signature': sig};

  WebhookSignatureFailure? checkAt(
    DateTime now,
    Map<String, String> headers, {
    List<int>? payload,
    String key = secret,
  }) => withClock(
    Clock.fixed(now),
    () => WebhookSignature(key).check(payload ?? body, headers),
  );

  group(WebhookSignature, () {
    test('accepts the Svix reference delivery', () {
      expect(checkAt(sentAt, headers()), isNull);
    });

    test('reads webhook-* headers and any header casing', () {
      expect(checkAt(sentAt, headers(prefix: 'webhook')), isNull);
      expect(checkAt(sentAt, headers(prefix: 'Svix')), isNull);
    });

    test('accepts a secret without the whsec_ prefix', () {
      expect(checkAt(sentAt, headers(), key: rawKey), isNull);
    });

    test('accepts when any one of several signatures matches', () {
      final rotated = 'v1,bm90IHRoZSBzaWduYXR1cmU= v2,ignored $signature';
      expect(checkAt(sentAt, headers(sig: rotated)), isNull);
    });

    test('refuses a changed body', () {
      expect(
        checkAt(sentAt, headers(), payload: utf8.encode('{"test": 1}')),
        WebhookSignatureFailure.noMatchingSignature,
      );
    });

    test('refuses a different secret', () {
      expect(
        checkAt(sentAt, headers(), key: 'whsec_${base64.encode([1, 2, 3])}'),
        WebhookSignatureFailure.noMatchingSignature,
      );
    });

    test('refuses malformed signature entries', () {
      expect(
        checkAt(sentAt, headers(sig: 'v1,%%% v1 nonsense')),
        WebhookSignatureFailure.noMatchingSignature,
      );
    });

    test('refuses missing headers', () {
      expect(
        checkAt(sentAt, {'svix-id': id}),
        WebhookSignatureFailure.missingHeaders,
      );
    });

    test('refuses a non-numeric timestamp', () {
      expect(
        checkAt(sentAt, headers(ts: 'yesterday')),
        WebhookSignatureFailure.invalidTimestamp,
      );
    });

    test('refuses timestamps outside the tolerance either way', () {
      const late = Duration(minutes: 5, seconds: 1);
      expect(
        checkAt(sentAt.add(late), headers()),
        WebhookSignatureFailure.timestampOutOfTolerance,
      );
      expect(
        checkAt(sentAt.subtract(late), headers()),
        WebhookSignatureFailure.timestampOutOfTolerance,
      );
      expect(
        checkAt(sentAt.add(const Duration(minutes: 5)), headers()),
        isNull,
      );
    });

    test('refuses extreme timestamps instead of throwing', () {
      for (final ts in ['99999999999999', '-9223372036854775808']) {
        expect(
          checkAt(sentAt, headers(ts: ts)),
          WebhookSignatureFailure.timestampOutOfTolerance,
        );
      }
      expect(
        checkAt(sentAt, headers(ts: '99999999999999999999')),
        WebhookSignatureFailure.invalidTimestamp,
      );
    });

    test('sign produces what check accepts', () {
      final at = DateTime.utc(2026, 10, 17, 12);
      final signer = WebhookSignature(secret);
      final sig = signer.sign('msg_1', at, body);
      final ts = '${at.millisecondsSinceEpoch ~/ 1000}';
      expect(
        checkAt(at, {
          'svix-id': 'msg_1',
          'svix-timestamp': ts,
          'svix-signature': sig,
        }),
        isNull,
      );
    });

    test('verify throws with the failure', () {
      expect(
        () => withClock(
          Clock.fixed(sentAt),
          () => WebhookSignature(secret).verify(body, {}),
        ),
        throwsA(
          isA<WebhookSignatureException>().having(
            (e) => e.failure,
            'failure',
            WebhookSignatureFailure.missingHeaders,
          ),
        ),
      );
    });
  });
}
