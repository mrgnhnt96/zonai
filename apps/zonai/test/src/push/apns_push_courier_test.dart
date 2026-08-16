/// APNs, spoken over a real HTTP/2 socket to something that answers like
/// Apple.
///
/// The provider token is checked with **openssl**, not with `jose`. That is
/// not a preference: `jose` signs a valid ES256 JWT — openssl verifies it —
/// but cannot verify its own output, so a `jose`-based check here would fail
/// on correct signatures and pass on nothing. Apple is the real verifier and
/// openssl is the closest stand-in for it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:clock/clock.dart';
import 'package:file/memory.dart';
import 'package:http2/http2.dart';
import 'package:test/test.dart';
import 'package:zonai/src/push/apns_provider_token.dart';
import 'package:zonai/src/push/apns_push_courier.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'fake_apns.dart';

/// A P-256 keypair in the shape Apple hands out: PKCS#8, no password.
({String private, String public})? _generateEcKeypair() {
  final dir = io.Directory.systemTemp.createTempSync('zonai_apns');
  try {
    final privatePath = '${dir.path}/key.p8';
    final publicPath = '${dir.path}/pub.pem';

    final gen = io.Process.runSync('openssl', [
      'genpkey',
      '-algorithm',
      'EC',
      '-pkeyopt',
      'ec_paramgen_curve:P-256',
      '-out',
      privatePath,
    ]);
    if (gen.exitCode != 0) return null;

    final pub = io.Process.runSync('openssl', [
      'ec',
      '-in',
      privatePath,
      '-pubout',
      '-out',
      publicPath,
    ]);
    if (pub.exitCode != 0) return null;

    return (
      private: io.File(privatePath).readAsStringSync(),
      public: io.File(publicPath).readAsStringSync(),
    );
  } on io.ProcessException {
    return null;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Verifies an ES256 compact JWS against a public PEM, the way Apple does.
///
/// The signature is raw `r||s`; openssl wants DER, so it is re-encoded here.
/// Doing that by hand is the price of not being able to use `jose`.
bool _verifyEs256(String jws, String publicPem) {
  final parts = jws.split('.');
  if (parts.length != 3) return false;

  final raw = base64Url.decode(base64Url.normalize(parts[2]));
  if (raw.length != 64) return false;

  List<int> derInt(List<int> value) {
    var v = value;
    while (v.length > 1 && v.first == 0) {
      v = v.sublist(1);
    }
    // ASN.1 INTEGER is signed, so a leading high bit needs a zero byte or the
    // value reads as negative.
    if (v.first & 0x80 != 0) v = [0, ...v];
    return [0x02, v.length, ...v];
  }

  final body = [...derInt(raw.sublist(0, 32)), ...derInt(raw.sublist(32))];
  final der = [0x30, body.length, ...body];

  final dir = io.Directory.systemTemp.createTempSync('zonai_apns_verify');
  try {
    io.File('${dir.path}/pub.pem').writeAsStringSync(publicPem);
    io.File('${dir.path}/sig.der').writeAsBytesSync(der);
    io.File(
      '${dir.path}/input.txt',
    ).writeAsStringSync('${parts[0]}.${parts[1]}');

    final result = io.Process.runSync('openssl', [
      'dgst',
      '-sha256',
      '-verify',
      '${dir.path}/pub.pem',
      '-signature',
      '${dir.path}/sig.der',
      '${dir.path}/input.txt',
    ]);
    return '${result.stdout}'.contains('Verified OK');
  } on io.ProcessException {
    return false;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

Map<String, dynamic> _claims(String jws) =>
    jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(jws.split('.')[1]))),
        )
        as Map<String, dynamic>;

Map<String, dynamic> _header(String jws) =>
    jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(jws.split('.')[0]))),
        )
        as Map<String, dynamic>;

void main() {
  late ({String private, String public})? keys;

  setUpAll(() {
    keys = _generateEcKeypair();
  });

  test('a keypair was actually generated (CI: skipping is failing)', () {
    if (keys != null) return;
    final ci = io.Platform.environment['CI'];
    if (ci == 'true' || ci == '1') {
      fail(
        'openssl is not on PATH, so every APNs test below skipped and this '
        'job proved nothing about the transport.',
      );
    }
    markTestSkipped('openssl is not on PATH (a gap, not a failure, locally)');
  });

  late FakeApns apns;
  late ApnsPushCourier courier;

  /// Boots a fake APNs and a courier wired to it over a real HTTP/2 socket.
  Future<PushConfig?> boot() async {
    if (keys case final keys?) {
      apns = await FakeApns.start();
      courier = ApnsPushCourier(
        fileSystem: MemoryFileSystem(),
        // Plain TCP rather than TLS: the protocol and the classification are
        // what is under test, and a self-signed certificate would only be
        // testing Dart's TLS stack.
        connect: (_) async => ClientTransportConnection.viaSocket(
          await io.Socket.connect(io.InternetAddress.loopbackIPv4, apns.port),
        ),
      );
      addTearDown(() async {
        await courier.close();
        await apns.stop();
      });

      return PushConfig(
        apns: ApnsConfig(
          credentials: ApnsCredentials.inline(keys.private),
          keyId: 'LALL9GMRMP',
          teamId: 'TEAMID1234',
          bundleId: 'dev.zonai.pushProbe',
        ),
        concurrency: 4,
      );
    }
    markTestSkipped('openssl is not on PATH, so nothing could be signed');
    return null;
  }

  const message = PushMessage(title: 'Direct', body: 'no firebase involved');

  group('the provider token', () {
    test('is an ES256 JWT Apple could verify', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(message, ['device-a'], config: config);

      final authorization = apns.authorizations.single;
      expect(authorization, startsWith('bearer '));

      final jws = authorization.substring('bearer '.length);
      expect(
        _verifyEs256(jws, keys!.public),
        isTrue,
        reason:
            'Apple holds only the public half. A signature it cannot verify '
            'is rejected as InvalidProviderToken, and nothing on our side '
            'would say why',
      );
    });

    test('carries kid in the header and iss in the body', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(message, ['device-a'], config: config);
      final jws = apns.authorizations.single.substring('bearer '.length);

      expect(_header(jws)['alg'], 'ES256');
      expect(
        _header(jws)['kid'],
        'LALL9GMRMP',
        reason:
            'the .p8 carries no id of its own, so the header is the only '
            'thing telling Apple which key to verify with',
      );
      expect(_claims(jws)['iss'], 'TEAMID1234');
      expect(_claims(jws)['iat'], isA<int>());
      expect(
        _claims(jws).containsKey('exp'),
        isFalse,
        reason: 'Apple sets the lifetime itself and refuses a token with one',
      );
    });

    test('one token serves a whole batch', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(message, [
        for (var i = 0; i < 10; i++) 'device-$i',
      ], config: config);

      expect(apns.requests, hasLength(10));
      expect(
        apns.authorizations.toSet(),
        hasLength(1),
        reason:
            'Apple refuses provider tokens regenerated more often than once '
            'per 20 minutes, so a token per send is not merely wasteful — it '
            'is rejected as TooManyProviderTokenUpdates',
      );
    });

    test('is reused until the refresh window, then minted again', () {
      if (keys case final keys?) {
        final token = ApnsProviderToken(
          privateKeyPem: keys.private,
          keyId: 'LALL9GMRMP',
          teamId: 'TEAMID1234',
        );

        final start = DateTime.utc(2026);
        final first = withClock(Clock.fixed(start), token.get);
        final soon = withClock(
          Clock.fixed(start.add(const Duration(minutes: 39))),
          token.get,
        );
        final later = withClock(
          Clock.fixed(start.add(const Duration(minutes: 41))),
          token.get,
        );

        expect(soon, first, reason: 'inside the window, the same token');
        expect(
          later,
          isNot(first),
          reason:
              'past it, a new one — Apple rejects a provider token older than '
              'an hour, and 40 minutes leaves room for a batch to finish',
        );
      } else {
        markTestSkipped('openssl is not on PATH');
      }
    });
  });

  group('the request', () {
    test('addresses the device and names the app', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(message, ['device-a'], config: config);
      final request = apns.requests.single;

      expect(request.path, '/3/device/device-a');
      expect(
        request.headers['apns-topic'],
        'dev.zonai.pushProbe',
        reason:
            'one key serves every app on a team, so the topic is the only '
            'thing saying which app this is for — APNs refuses a send '
            'without it',
      );
      expect(
        request.headers['apns-push-type'],
        'alert',
        reason: 'iOS 13+ rejects a send whose push type does not match',
      );
    });

    test(
      'is the aps envelope, with data beside it rather than inside',
      () async {
        final config = await boot();
        if (config == null) return;

        await courier.send(
          const PushMessage(
            title: 'New reply',
            body: 'Someone replied',
            data: {'postId': '42'},
          ),
          ['device-a'],
          config: config,
        );

        final body = apns.requests.single.body;
        expect((body['aps'] as Map)['alert'], {
          'title': 'New reply',
          'body': 'Someone replied',
        });
        expect(
          body['postId'],
          '42',
          reason:
              'APNs expects custom keys at the top level, unlike FCM which '
              'nests them under `data`. An app reading both transports should '
              'see the same keys either way',
        );
      },
    );

    test('a collapse key travels as apns-collapse-id', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(
        const PushMessage(title: 'a', body: 'b', collapseKey: 'thread:7'),
        ['device-a'],
        config: config,
      );

      expect(apns.requests.single.headers['apns-collapse-id'], 'thread:7');
    });
  });

  group('classification', () {
    test('a mixed batch comes back aligned with the tokens given', () async {
      final config = await boot();
      if (config == null) return;

      apns.replyFor = (token) => switch (token) {
        'gone' => apnsError(410, 'Unregistered'),
        'bad-token' => apnsError(400, 'BadDeviceToken'),
        'too-big' => apnsError(413, 'PayloadTooLarge'),
        'busy' => apnsError(429, 'TooManyRequests'),
        _ => apnsOk,
      };

      final tokens = ['good', 'gone', 'bad-token', 'too-big', 'busy', 'fine'];
      final outcomes = await courier.send(message, tokens, config: config);

      // Alignment is the contract: the engine prunes by position, so an
      // outcome landing one slot over clears the wrong device's row.
      expect([for (final o in outcomes) o.token], tokens);
      expect(outcomes[0], isA<PushDelivered>());
      expect(
        outcomes[1],
        isA<PushPermanentlyRejected>().having(
          (o) => o.reason,
          'reason',
          PushRejectionReason.unregistered,
        ),
      );
      expect(
        outcomes[2],
        isA<PushPermanentlyRejected>().having(
          (o) => o.reason,
          'reason',
          PushRejectionReason.unregistered,
        ),
        reason: 'BadDeviceToken is as final as Unregistered',
      );
      expect(
        outcomes[3],
        isA<PushPermanentlyRejected>().having(
          (o) => o.reason,
          'reason',
          PushRejectionReason.invalidArgument,
        ),
        reason: 'the notification was wrong, not the device',
      );
      expect(outcomes[4], isA<PushTransientlyFailed>());
      expect(outcomes[5], isA<PushDelivered>());
    });

    test('a bundleId mismatch is transient, never a prune', () async {
      final config = await boot();
      if (config == null) return;

      // Measured live against api.sandbox.push.apple.com on 2026-08-15, with
      // one key and one device token:
      //
      //   topic the team does not own -> 400 TopicDisallowed
      //   topic it owns, token from
      //   a different app             -> 400 DeviceTokenNotForTopic
      //
      // So this reason is produced by a `bundleId` that disagrees with the
      // app — a config fault, and a uniform one. Every iOS recipient returns
      // it at once, so a permanent reading would prune every iOS
      // registration in the table in a single drain.
      apns.replyFor = (_) => apnsError(400, 'DeviceTokenNotForTopic');

      final outcomes = await courier.send(message, [
        'a',
        'b',
        'c',
      ], config: config);

      expect(
        outcomes,
        everyElement(isA<PushTransientlyFailed>()),
        reason:
            'the tokens are valid for some app; it is the topic that is '
            'wrong, and it self-corrects the moment the config is right',
      );
      expect(
        (outcomes.first as PushTransientlyFailed).detail,
        contains('bundleId'),
        reason:
            'the message has to name the config field, or someone goes '
            'looking at devices for a mistake that is in a yaml file',
      );
    });

    test('a bad provider token fails the job, blaming no device', () async {
      final config = await boot();
      if (config == null) return;

      apns.replyFor = (_) => apnsError(403, 'InvalidProviderToken');

      await expectLater(
        courier.send(message, ['a', 'b', 'c'], config: config),
        throwsA(isA<PushTransportException>()),
        reason:
            'the key is wrong, not the devices. Classifying this per token '
            'would prune every iOS registration in the table over a mistyped '
            'key id',
      );
    });

    test('an unrecognised reason is transient, not a prune', () async {
      final config = await boot();
      if (config == null) return;

      apns.replyFor = (_) => apnsError(400, 'SomeReasonAppleAddedLater');

      final outcomes = await courier.send(message, ['a'], config: config);

      expect(
        outcomes.single,
        isA<PushTransientlyFailed>(),
        reason:
            'these mappings come from documentation, and the FCM table '
            'written the same way was wrong three times. An unknown reason '
            'costs a retry; guessing permanent costs a device forever',
      );
    });

    test('an unreachable APNs fails every token transiently', () async {
      if (keys == null) {
        markTestSkipped('openssl is not on PATH');
        return;
      }

      final unreachable = ApnsPushCourier(
        fileSystem: MemoryFileSystem(),
        connect: (_) async => throw const io.SocketException('refused'),
      );
      addTearDown(unreachable.close);

      final outcomes = await unreachable.send(
        message,
        ['a', 'b'],
        config: PushConfig(
          apns: ApnsConfig(
            credentials: ApnsCredentials.inline(keys!.private),
            keyId: 'LALL9GMRMP',
            teamId: 'TEAMID1234',
            bundleId: 'dev.zonai.pushProbe',
          ),
        ),
      );

      expect(outcomes, everyElement(isA<PushTransientlyFailed>()));
      expect(
        outcomes.map((o) => o.token),
        ['a', 'b'],
        reason: 'not reaching Apple is nobody\'s token being at fault',
      );
    });
  });

  group('credentials', () {
    test('a missing key file names the file rather than the exception', () {
      final courier = ApnsPushCourier(fileSystem: MemoryFileSystem());
      addTearDown(courier.close);

      expect(
        () => courier.send(
          message,
          ['a'],
          config: const PushConfig(
            apns: ApnsConfig(
              credentials: ApnsCredentials.file('/etc/nope/AuthKey.p8'),
              keyId: 'LALL9GMRMP',
              teamId: 'TEAMID1234',
              bundleId: 'dev.zonai.pushProbe',
            ),
          ),
        ),
        throwsA(
          isA<PushTransportException>().having(
            (e) => e.toString(),
            'message',
            contains('/etc/nope/AuthKey.p8'),
          ),
        ),
      );
    });

    test('a private key never appears in an error message', () {
      final courier = ApnsPushCourier(fileSystem: MemoryFileSystem());
      addTearDown(courier.close);

      const notAKey = 'PRIVATE-MATERIAL-THAT-MUST-NOT-LEAK';
      expect(
        () => courier.send(
          message,
          ['a'],
          config: const PushConfig(
            apns: ApnsConfig(
              credentials: ApnsCredentials.inline(notAKey),
              keyId: 'LALL9GMRMP',
              teamId: 'TEAMID1234',
              bundleId: 'dev.zonai.pushProbe',
            ),
          ),
        ),
        throwsA(
          isA<PushTransportException>().having(
            (e) => e.toString(),
            'message',
            isNot(contains(notAKey)),
          ),
        ),
      );
    });
  });
}
