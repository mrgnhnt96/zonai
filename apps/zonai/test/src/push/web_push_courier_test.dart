/// Web Push against RFC 8291's worked example, and against a fake push
/// service that decrypts what it is sent the way a browser would.
///
/// The JWT is verified with pointycastle's ECDSA, not with `jose`, which
/// signed it: a check by the same library would agree with itself whatever
/// it produced.
library;

import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file/memory.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai/src/push/web_push_courier.dart';
import 'package:zonai/src/push/web_push_crypto.dart';
import 'package:zonai_schema/zonai_schema.dart';

// RFC 8291 §5 and Appendix A.
const _asPrivate = 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw';
const _asPublic =
    'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8';
const _uaPrivate = 'q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94';
const _uaPublic =
    'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4';
const _salt = 'DGv6ra1nlYgDCS1FRnbzlw';
const _authSecret = 'BTBZMqHH6r4Tts7J_aSIgg';
const _rfcBody =
    'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml'
    'mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT'
    'pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN';

/// A second P-256 pair, as `openssl ecparam -genkey` writes it, in both PEM
/// forms a deploy might hold.
const _pemPublic =
    'BO_dZrvdyPvNnVs0Mk_EO_aHQjApRbrl_AoLjSheGiV2M3Ld7YikQC8oUrCZ1BayPEiHUThfNJ50SacBxyk0yqw';
const _pkcs8Pem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgVxHVAqZEy1d6YADE
WRdXCrumn6B80H3EKTdzM7hYMVOhRANCAATv3Wa73cj7zZ1bNDJPxDv2h0IwKUW6
5fwKC40oXholdjNy3e2IpEAvKFKwmdQWsjxIh1E4XzSedEmnAccpNMqs
-----END PRIVATE KEY-----
''';
const _sec1Pem = '''
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIFcR1QKmRMtXemAAxFkXVwq7pp+gfNB9xCk3czO4WDFToAoGCCqGSM49
AwEHoUQDQgAE791mu93I+82dWzQyT8Q79odCMClFuuX8CguNKF4aJXYzct3tiKRA
LyhSsJnUFrI8SIdROF80nnRJpwHHKTTKrA==
-----END EC PRIVATE KEY-----
''';

const _subject = 'mailto:ops@example.com';

PushConfig _config({
  String publicKey = _asPublic,
  WebPushPrivateKey privateKey = const WebPushPrivateKey.inline(_asPrivate),
}) => PushConfig(
  webPush: WebPushConfig(
    publicKey: publicKey,
    privateKey: privateKey,
    subject: _subject,
  ),
);

/// A subscription whose browser half is RFC 8291's user agent, so the fake
/// push service can decrypt what it receives.
String _subscription({String endpoint = 'https://push.example.net/push/abc'}) =>
    jsonEncode({
      'endpoint': endpoint,
      'expirationTime': null,
      'keys': {'p256dh': _uaPublic, 'auth': _authSecret},
    });

final _p256 = ECDomainParameters('prime256v1');

Uint8List _b64(String value) => decodeBase64Url(value)!;

BigInt _int(List<int> bytes) =>
    bytes.fold(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));

Uint8List _hmac(List<int> key, List<int> data) =>
    Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(data).bytes);

/// What a browser does with a push body: RFC 8291 in reverse, with the user
/// agent's private key.
String _decrypt(Uint8List body) {
  final salt = body.sublist(0, 16);
  final idLength = body[20];
  final asPublic = body.sublist(21, 21 + idLength);
  final ciphertext = body.sublist(21 + idLength);

  final shared =
      (ECDHBasicAgreement()..init(ECPrivateKey(_int(_b64(_uaPrivate)), _p256)))
          .calculateAgreement(
            ECPublicKey(_p256.curve.decodePoint(asPublic), _p256),
          );
  final ecdh = Uint8List(32);
  var v = shared;
  for (var i = 31; i >= 0; i--) {
    ecdh[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }

  final ua = _b64(_uaPublic);
  final prkKey = _hmac(_b64(_authSecret), ecdh);
  final ikm = _hmac(prkKey, [
    ...utf8.encode('WebPush: info'),
    0,
    ...ua,
    ...asPublic,
    1,
  ]);
  final prk = _hmac(salt, ikm);
  final cek = _hmac(prk, [
    ...utf8.encode('Content-Encoding: aes128gcm'),
    0,
    1,
  ]).sublist(0, 16);
  final nonce = _hmac(prk, [
    ...utf8.encode('Content-Encoding: nonce'),
    0,
    1,
  ]).sublist(0, 12);

  final plain =
      (GCMBlockCipher(AESEngine())..init(
            false,
            AEADParameters(KeyParameter(cek), 128, nonce, Uint8List(0)),
          ))
          .process(ciphertext);
  expect(plain.last, 2, reason: 'last-record delimiter');
  return utf8.decode(plain.sublist(0, plain.length - 1));
}

/// Verifies an ES256 compact JWS against a raw uncompressed public key.
bool _verifyEs256(String jws, String publicKey) {
  final parts = jws.split('.');
  final signature = _b64(parts[2]);
  final point = _p256.curve.decodePoint(_b64(publicKey));
  final verifier = Signer('SHA-256/ECDSA')
    ..init(false, PublicKeyParameter(ECPublicKey(point, _p256)));
  return verifier.verifySignature(
    Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
    ECSignature(_int(signature.sublist(0, 32)), _int(signature.sublist(32))),
  );
}

Map<String, dynamic> _segment(String jws, int index) =>
    jsonDecode(utf8.decode(_b64(jws.split('.')[index])))
        as Map<String, dynamic>;

/// A courier talking to a push service that answers [status] (or whatever
/// [respond] says), recording every request it receives.
(WebPushCourier, List<http.Request>) _courier({
  int status = 201,
  http.Response Function(http.Request)? respond,
}) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return respond?.call(request) ?? http.Response('', status);
  });
  return (
    WebPushCourier(fileSystem: MemoryFileSystem(), client: client),
    requests,
  );
}

const _message = PushMessage(
  title: 'Dentist at 3',
  body: 'In 30 minutes',
  collapseKey: 'event-42',
  data: {'eventId': '42'},
);

void main() {
  group('encryptWebPushPayload', () {
    test('reproduces RFC 8291 §5 byte for byte', () {
      final body = encryptWebPushPayload(
        plaintext: utf8.encode('When I grow up, I want to be a watermelon'),
        p256dh: _b64(_uaPublic),
        auth: _b64(_authSecret),
        senderPrivate: _int(_b64(_asPrivate)),
        salt: _b64(_salt),
      );

      expect(encodeBase64Url(body), _rfcBody);
    });

    test(
      'a fresh key and salt each time, and the browser can still read it',
      () {
        List<int> encrypt() => encryptWebPushPayload(
          plaintext: utf8.encode('hello'),
          p256dh: _b64(_uaPublic),
          auth: _b64(_authSecret),
        );
        final a = Uint8List.fromList(encrypt());
        final b = Uint8List.fromList(encrypt());

        expect(a.sublist(0, 16), isNot(b.sublist(0, 16)), reason: 'salt');
        expect(_decrypt(a), 'hello');
        expect(_decrypt(b), 'hello');
      },
    );
  });

  group('WebPushCourier.send', () {
    test(
      'posts an aes128gcm body the browser decrypts to the payload',
      () async {
        final (courier, requests) = _courier();

        final outcomes = await courier.send(_message, [
          _subscription(),
        ], config: _config());

        expect(outcomes.single, isA<PushDelivered>());
        final request = requests.single;
        expect(request.method, 'POST');
        expect(request.url, Uri.parse('https://push.example.net/push/abc'));
        expect(jsonDecode(_decrypt(request.bodyBytes)), {
          'title': 'Dentist at 3',
          'body': 'In 30 minutes',
          'tag': 'event-42',
          'data': {'eventId': '42'},
        });
      },
    );

    test('sends the RFC 8030 headers', () async {
      final (courier, requests) = _courier();

      await courier.send(_message, [_subscription()], config: _config());

      final headers = requests.single.headers;
      expect(headers['Content-Encoding'], 'aes128gcm');
      expect(headers['TTL'], '86400');
      expect(headers['Urgency'], 'high');
      expect(headers['Topic'], 'event-42');
    });

    test('a message with no collapse key has no tag and no Topic', () async {
      final (courier, requests) = _courier();

      await courier.send(const PushMessage(title: 't', body: 'b'), [
        _subscription(),
      ], config: _config());

      expect(requests.single.headers.containsKey('Topic'), isFalse);
      expect(
        (jsonDecode(_decrypt(requests.single.bodyBytes)) as Map).containsKey(
          'tag',
        ),
        isFalse,
      );
    });

    test('signs a VAPID JWT for the endpoint origin', () async {
      final (courier, requests) = _courier();

      await withClock(Clock.fixed(DateTime.utc(2026, 11, 23, 12)), () async {
        await courier.send(_message, [
          _subscription(endpoint: 'https://push.example.net:8443/push/abc'),
        ], config: _config());
      });

      final auth = requests.single.headers['Authorization']!;
      final match = RegExp(r'^vapid t=([^,]+), k=(.+)$').firstMatch(auth);
      expect(match, isNotNull, reason: auth);
      final jwt = match!.group(1)!;

      expect(match.group(2), _asPublic);
      expect(_segment(jwt, 0)['alg'], 'ES256');
      final claims = _segment(jwt, 1);
      expect(claims['aud'], 'https://push.example.net:8443');
      expect(claims['sub'], _subject);
      final issued =
          DateTime.utc(2026, 11, 23, 12).millisecondsSinceEpoch ~/ 1000;
      expect(claims['exp'], greaterThan(issued));
      expect(claims['exp'], lessThanOrEqualTo(issued + 24 * 3600));
      expect(_verifyEs256(jwt, _asPublic), isTrue);
    });

    test('mints one JWT per push service and reuses it', () async {
      final (courier, requests) = _courier();

      await courier.send(_message, [
        _subscription(endpoint: 'https://fcm.googleapis.com/fcm/send/a'),
        _subscription(endpoint: 'https://fcm.googleapis.com/fcm/send/b'),
        _subscription(endpoint: 'https://updates.push.services.mozilla.com/x'),
      ], config: _config());

      String jwtOf(http.Request r) =>
          r.headers['Authorization']!.split('t=')[1].split(',').first;
      final byUrl = {for (final r in requests) r.url.host: <String>{}};
      for (final r in requests) {
        byUrl[r.url.host]!.add(jwtOf(r));
      }
      expect(byUrl['fcm.googleapis.com'], hasLength(1));
      expect(
        _segment(byUrl['updates.push.services.mozilla.com']!.single, 1)['aud'],
        'https://updates.push.services.mozilla.com',
      );
    });

    test('hashes a collapse key that is not a valid Topic', () async {
      final (courier, requests) = _courier();
      const long = 'reminder:todo/123 for person 456, morning edition';

      await courier.send(
        const PushMessage(title: 't', body: 'b', collapseKey: long),
        [_subscription(), _subscription()],
        config: _config(),
      );

      final topics = {for (final r in requests) r.headers['Topic']};
      expect(topics, hasLength(1), reason: 'same key, same topic');
      expect(topics.single, matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));
    });

    test(
      'accepts the private key as PKCS#8 or SEC1 PEM, inline or file',
      () async {
        final fs = MemoryFileSystem()
          ..file('/vapid.pem').writeAsStringSync(_sec1Pem);
        for (final key in const [
          WebPushPrivateKey.inline(_pkcs8Pem),
          WebPushPrivateKey.inline(_sec1Pem),
          WebPushPrivateKey.file('/vapid.pem'),
        ]) {
          final requests = <http.Request>[];
          final courier = WebPushCourier(
            fileSystem: fs,
            client: MockClient((r) async {
              requests.add(r);
              return http.Response('', 201);
            }),
          );

          final outcomes = await courier.send(_message, [
            _subscription(),
          ], config: _config(publicKey: _pemPublic, privateKey: key));

          expect(outcomes.single, isA<PushDelivered>(), reason: '$key');
          final jwt = requests.single.headers['Authorization']!
              .split('t=')[1]
              .split(',')
              .first;
          expect(_verifyEs256(jwt, _pemPublic), isTrue, reason: '$key');
        }
      },
    );

    test('a key pair that does not match fails the job, not a row', () async {
      final (courier, requests) = _courier();

      await expectLater(
        courier.send(_message, [
          _subscription(),
        ], config: _config(publicKey: _pemPublic)),
        throwsA(
          isA<PushTransportException>().having(
            (e) => e.message,
            'message',
            contains('does not match'),
          ),
        ),
      );
      expect(requests, isEmpty);
    });

    test('a missing key file fails the job', () async {
      final (courier, _) = _courier();

      await expectLater(
        courier.send(_message, [
          _subscription(),
        ], config: _config(privateKey: const WebPushPrivateKey.file('/nope'))),
        throwsA(isA<PushTransportException>()),
      );
    });

    test('with no webPush config it refuses rather than guessing', () async {
      final (courier, _) = _courier();

      await expectLater(
        courier.send(_message, [_subscription()], config: const PushConfig()),
        throwsA(isA<PushTransportException>()),
      );
    });
  });

  group('a token that is not a subscription', () {
    for (final (name, token) in [
      ('not JSON', 'fcm-registration-token'),
      ('no endpoint', jsonEncode({'keys': {}})),
      (
        'an http endpoint',
        jsonEncode({
          'endpoint': 'http://10.0.0.1/admin',
          'keys': {'p256dh': _uaPublic, 'auth': _authSecret},
        }),
      ),
      (
        'a short p256dh',
        jsonEncode({
          'endpoint': 'https://push.example.net/x',
          'keys': {'p256dh': _authSecret, 'auth': _authSecret},
        }),
      ),
      (
        'no auth',
        jsonEncode({
          'endpoint': 'https://push.example.net/x',
          'keys': {'p256dh': _uaPublic},
        }),
      ),
    ]) {
      test('$name is that row\'s problem only', () async {
        final (courier, requests) = _courier();

        final outcomes = await courier.send(_message, [
          token,
          _subscription(),
        ], config: _config());

        expect(
          outcomes.first,
          isA<PushTransientlyFailed>().having(
            (o) => o.detail,
            'detail',
            contains('not a Web Push subscription'),
          ),
        );
        expect(outcomes.last, isA<PushDelivered>());
        expect(requests, hasLength(1), reason: 'only the good row is sent');
      });
    }
  });

  group('push service answers', () {
    Future<PushOutcome> answer(int status, [String body = '']) async {
      final (courier, _) = _courier(
        respond: (_) => http.Response(body, status),
      );
      final outcomes = await courier.send(_message, [
        _subscription(),
      ], config: _config());
      return outcomes.single;
    }

    for (final status in [200, 201, 202]) {
      test('$status is delivered', () async {
        expect(await answer(status), isA<PushDelivered>());
      });
    }

    for (final status in [404, 410]) {
      test('$status is a permanent rejection', () async {
        expect(
          await answer(status),
          isA<PushPermanentlyRejected>().having(
            (o) => o.reason,
            'reason',
            PushRejectionReason.unregistered,
          ),
        );
      });
    }

    for (final status in [400, 401, 403, 413, 429, 500, 502, 503]) {
      test('$status is transient, never a prune', () async {
        expect(await answer(status), isA<PushTransientlyFailed>());
      });
    }

    test('403 says VAPID and quotes the push service', () async {
      expect(
        await answer(403, 'the key in the authorization header does not match'),
        isA<PushTransientlyFailed>().having(
          (o) => o.detail,
          'detail',
          allOf(contains('VAPID'), contains('does not match')),
        ),
      );
    });

    test('a network failure is transient', () async {
      final courier = WebPushCourier(
        fileSystem: MemoryFileSystem(),
        client: MockClient((_) async => throw const io.SocketException('down')),
      );

      final outcomes = await courier.send(_message, [
        _subscription(),
      ], config: _config());

      expect(outcomes.single, isA<PushTransientlyFailed>());
    });
  });
}
