/// The transport against a **real socket**, talking to something that speaks
/// FCM's protocol back.
///
/// `fcm_push_courier_test.dart` substitutes `http.Client`, so everything it
/// asserts stops at the boundary of our own code: it can prove we *built* a
/// request, never that the request is one Google would accept. Two whole
/// classes of defect live past that boundary and neither is reachable from a
/// stubbed client:
///
///   1. The assertion is signed but not *verifiable*. A wrong algorithm, a
///      malformed header, a claim set Google rejects — a stub returns 200 to
///      all of it, because a stub never checks a signature. Here the token
///      endpoint holds only the **public** key and verifies for real, which is
///      exactly the check Google performs and the one that has never run.
///   2. The two halves are wired to each other wrong. The access token minted
///      by one request has to arrive as the `Authorization` header of the
///      next; nothing before this file has watched both requests land.
///
/// What it still cannot prove: that Google's servers behave the way their
/// documentation says. The status strings this file returns are transcribed
/// from that documentation, so a mistake in the transcription is invisible
/// here and would be equally invisible in any test that does not send a real
/// notification to a real device. That gap is real, and it is recorded in
/// `todo.md` rather than papered over.
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:zonai/src/push/fcm_push_courier.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'fake_fcm.dart';

void main() {
  late ({String private, String public})? keypair;

  setUpAll(() {
    keypair = generateKeypair();
  });

  // Same reasoning as the sibling file: on CI a silent skip would mean the
  // whole wire suite proved nothing while the job went green.
  test('a keypair was actually generated (CI: skipping is failing)', () {
    if (keypair != null) return;

    final ci = io.Platform.environment['CI'];
    if (ci == 'true' || ci == '1') {
      fail(
        'openssl is not on PATH, so every wire test below skipped and this '
        'job proved nothing about the FCM transport.',
      );
    }
    markTestSkipped('openssl is not on PATH (a gap, not a failure, locally)');
  });

  late FakeFcm fcm;
  late FcmPushCourier courier;

  /// Boots a fake FCM and a courier pointed at it, or skips when there is no
  /// keypair to sign with. Returns null after marking the test skipped.
  Future<PushConfig?> boot() async {
    if (keypair case final keys?) {
      fcm = await FakeFcm.start(publicKeyPem: keys.public);
      courier = FcmPushCourier(
        fileSystem: MemoryFileSystem(),
        baseUri: fcm.baseUri,
      );
      addTearDown(() async {
        await courier.close();
        await fcm.stop();
      });

      return PushConfig(
        projectId: 'wire-project',
        credentials: PushCredentials.inline(
          serviceAccountJson(privateKey: keys.private, tokenUri: fcm.tokenUri),
        ),
        concurrency: 4,
      );
    }

    markTestSkipped('openssl is not on PATH, so nothing could be signed');
    return null;
  }

  const message = PushMessage(title: 'Wire', body: 'over a real socket');

  group('the service-account assertion', () {
    test('verifies against the public key alone', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(message, ['token-a'], config: config);

      expect(
        fcm.assertionRejection,
        isNull,
        reason: 'the assertion we sign must be one Google can verify',
      );
      expect(
        fcm.verifiedAssertions,
        hasLength(1),
        reason:
            'a stubbed http client cannot fail this: it never checks a '
            'signature, so a wrongly-signed assertion looks identical to a '
            'correct one until something holding the public key looks at it',
      );
    });

    test('carries the claims Google requires to issue a token', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(message, ['token-a'], config: config);

      final claims = fcm.verifiedAssertions.single;
      expect(claims['iss'], 'wire@wire-project.iam.gserviceaccount.com');
      expect(claims['aud'], fcm.tokenUri);
      expect(
        claims['scope'],
        'https://www.googleapis.com/auth/firebase.messaging',
        reason:
            'the wrong scope mints a token that is rejected only later, at '
            'send time, as a 403 — which this codebase treats as a '
            'credentials failure rather than a per-token one',
      );

      final issuedAt = claims['iat'] as int;
      final expiresAt = claims['exp'] as int;
      expect(
        expiresAt,
        greaterThan(issuedAt),
        reason: 'an already-expired assertion is refused outright',
      );
    });

    test('a rejected assertion surfaces as a transport failure', () async {
      final config = await boot();
      if (config == null) return;
      fcm.rejectAssertion = true;

      await expectLater(
        courier.send(message, ['token-a'], config: config),
        throwsA(
          isA<PushTransportException>().having(
            (e) => e.toString(),
            'message',
            contains('invalid_grant'),
          ),
        ),
      );

      expect(
        fcm.sends,
        isEmpty,
        reason: 'no token, no send — and no tokens blamed for a key problem',
      );
    });
  });

  group('the two requests are wired to each other', () {
    test('the issued access token is the one presented to send', () async {
      final config = await boot();
      if (config == null) return;
      fcm.issuedAccessToken = 'the-one-and-only-token';

      final outcomes = await courier.send(message, ['token-a'], config: config);

      expect(
        fcm.sends.single.authorization,
        'Bearer the-one-and-only-token',
        reason:
            'the mint and the send are separate requests; nothing before this '
            'file watched both of them land',
      );
      expect(outcomes.single, isA<PushDelivered>());
    });

    test('the send addresses the configured project', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(message, ['token-a'], config: config);

      expect(
        fcm.sends.single.path,
        '/v1/projects/wire-project/messages:send',
        reason:
            'a colon in the last path segment is the part a URI builder is '
            'most likely to percent-encode into a 404',
      );
    });

    test('one mint serves a whole batch', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(message, [
        for (var i = 0; i < 12; i++) 'token-$i',
      ], config: config);

      expect(fcm.sends, hasLength(12));
      expect(
        fcm.tokenRequests,
        hasLength(1),
        reason:
            'caching is required, not an optimisation — a mint per send is a '
            'signature and a round trip per recipient',
      );
    });
  });

  group('the wire body', () {
    test('is the {"message": {...}} envelope FCM documents', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(
        const PushMessage(
          title: 'New reply',
          body: 'Someone replied to you',
          data: {'postId': '42'},
        ),
        ['token-a'],
        config: config,
      );

      final body = fcm.sends.single.body;
      expect(body.keys, ['message']);

      final envelope = body['message'] as Map;
      expect(envelope['token'], 'token-a');
      expect(envelope['notification'], {
        'title': 'New reply',
        'body': 'Someone replied to you',
      });
      expect(envelope['data'], {'postId': '42'});
    });

    test('a collapse key travels for both platforms at once', () async {
      final config = await boot();
      if (config == null) return;

      await courier.send(
        const PushMessage(title: 'a', body: 'b', collapseKey: 'thread:7'),
        ['token-a'],
        config: config,
      );

      final envelope = fcm.sends.single.body['message'] as Map;
      expect((envelope['android'] as Map)['collapse_key'], 'thread:7');
      expect(
        ((envelope['apns'] as Map)['headers'] as Map)['apns-collapse-id'],
        'thread:7',
        reason:
            'setting only one leaves duplicate notifications stacked up on '
            'the other platform, which is the bug collapsing exists to fix',
      );
    });
  });

  group('classification over a real socket', () {
    test('a mixed batch comes back aligned with the tokens given', () async {
      final config = await boot();
      if (config == null) return;

      fcm.replyFor = (token) => switch (token) {
        'gone' => errReply(404, 'UNREGISTERED'),
        // Both 404 spellings, on purpose: a live probe against real FCM
        // returned NOT_FOUND — not UNREGISTERED — for a token it had never
        // issued, so this is the one the pruning path actually meets.
        'never-issued' => errReply(404, 'NOT_FOUND'),
        'malformed' => errReply(400, 'INVALID_ARGUMENT'),
        'flaky' => errReply(503, 'UNAVAILABLE'),
        _ => okReply,
      };

      final tokens = [
        'good',
        'gone',
        'never-issued',
        'malformed',
        'flaky',
        'also-good',
      ];
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
        reason: 'NOT_FOUND prunes exactly as UNREGISTERED does',
      );
      expect(
        outcomes[3],
        isA<PushPermanentlyRejected>().having(
          (o) => o.reason,
          'reason',
          PushRejectionReason.invalidArgument,
        ),
      );
      expect(outcomes[4], isA<PushTransientlyFailed>());
      expect(outcomes[5], isA<PushDelivered>());
    });

    test('a missing APNs key does not take the batch down with it', () async {
      final config = await boot();
      if (config == null) return;

      // Real FCM, 2026-08-15: an iOS token in a project with no APNs key
      // uploaded answers 401 UNAUTHENTICATED with errorCode
      // THIRD_PARTY_AUTH_ERROR, while a bogus token in the same minute
      // answers 404 — so the caller's credentials were fine and only one
      // platform was misconfigured.
      fcm.replyFor = (token) => token == 'ios'
          ? errReply(
              401,
              'UNAUTHENTICATED',
              errorCode: 'THIRD_PARTY_AUTH_ERROR',
            )
          : okReply;

      final outcomes = await courier.send(message, [
        'android',
        'ios',
      ], config: config);

      expect(
        outcomes[0],
        isA<PushDelivered>(),
        reason: 'one broken platform must not stop the other being notified',
      );
      expect(
        outcomes[1],
        isA<PushTransientlyFailed>(),
        reason:
            'transient, never permanent — the device token is valid and it '
            'is the project that is missing a key, so pruning would clear '
            'every iOS registration over a lapsed credential',
      );
    });

    test('a 401 on send throws rather than blaming the tokens', () async {
      final config = await boot();
      if (config == null) return;

      // The server hands out one token and then only accepts a different one,
      // which is what an expired or wrongly-scoped credential looks like from
      // the courier's side.
      fcm.issuedAccessToken = 'stale';
      await courier.send(message, ['warm-the-cache'], config: config);
      fcm.issuedAccessToken = 'rotated';

      await expectLater(
        courier.send(message, ['a', 'b', 'c'], config: config),
        throwsA(isA<PushTransportException>()),
        reason:
            'classifying a credentials failure per token would prune every '
            'recipient in the batch over a config mistake',
      );
    });
  });
}
