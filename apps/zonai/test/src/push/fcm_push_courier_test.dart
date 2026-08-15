import 'dart:convert';
import 'dart:io' as io;

import 'package:clock/clock.dart';
import 'package:file/memory.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:zonai/src/push/fcm_access_token.dart';
import 'package:zonai/src/push/fcm_push_courier.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The transport, against a client that never touches the network.
///
/// These are the assertions §12 lists first, and the reason `PushCourier` is
/// an interface at all: the email courier has no equivalent, so nothing in
/// the suite covers a successful send, a rejection, or a retry there.

/// A throwaway RSA private key, generated fresh for each run.
///
/// Signing an assertion needs a real key — `JsonWebKey.fromPem` parses one,
/// and a fake string fails before any of the caching behaviour below can be
/// observed. Generating it rather than committing it is deliberate: §12 ends
/// with "no key material in a test fixture", and the reason is that a reader
/// cannot tell a throwaway key from a real one at a glance, so the habit is
/// the hazard rather than any one key.
///
/// Returns null when `openssl` is not on PATH, and the tests that need it
/// skip rather than fail.
String? _generateRsaPrivateKeyPem() {
  try {
    final result = io.Process.runSync('openssl', const [
      'genpkey',
      '-algorithm',
      'RSA',
      '-pkeyopt',
      'rsa_keygen_bits:2048',
    ]);
    if (result.exitCode != 0) return null;
    final pem = '${result.stdout}';
    return pem.contains('BEGIN PRIVATE KEY') ? pem : null;
  } on io.ProcessException {
    return null;
  }
}

String _serviceAccountJson({required String privateKey}) => jsonEncode({
  'type': 'service_account',
  'project_id': 'fixture-project',
  'client_email': 'fixture@fixture-project.iam.gserviceaccount.com',
  'private_key': privateKey,
  'token_uri': 'https://oauth2.example/token',
});

/// Answers requests from a queue of canned responses, recording every one.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final http.Response Function(http.BaseRequest request, String body) handler;
  final requests = <({http.BaseRequest request, String body})>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = switch (request) {
      final http.Request request => request.body,
      _ => '',
    };
    requests.add((request: request, body: body));

    final response = handler(request, body);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  int get tokenRequests =>
      requests.where((r) => r.request.url.path.endsWith('/token')).length;

  int get sendRequests =>
      requests.where((r) => r.request.url.path.endsWith('messages:send')).length;
}

http.Response _tokenResponse({int expiresIn = 3600}) => http.Response(
  jsonEncode({'access_token': 'access-token', 'expires_in': expiresIn}),
  200,
);

http.Response _fcmError(int status, String errorStatus) => http.Response(
  jsonEncode({
    'error': {'code': status, 'status': errorStatus, 'message': 'nope'},
  }),
  status,
);

/// FCM's real shape for a platform-credential problem: a 401 whose meaning
/// lives in `details[].errorCode` rather than in `status`.
http.Response _thirdPartyAuthError() => http.Response(
  jsonEncode({
    'error': {
      'code': 401,
      'message': 'Invalid APNs credential.',
      'status': 'UNAUTHENTICATED',
      'details': [
        {
          '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
          'errorCode': 'THIRD_PARTY_AUTH_ERROR',
        },
      ],
    },
  }),
  401,
);

PushConfig _config({required String privateKey}) => PushConfig(
  projectId: 'fixture-project',
  credentials: PushCredentials.inline(
    _serviceAccountJson(privateKey: privateKey),
  ),
  concurrency: 4,
);

void main() {
  // Every test needs a signable key. Generated once, in-process, rather than
  // committed: §12 ends with "no key material in a test fixture, a doc
  // example, or a committed config", and a private key pasted into a test
  // file is exactly the habit that rule exists to prevent — a reader cannot
  // tell a throwaway one from a real one at a glance.
  late String? generatedKey;

  setUpAll(() {
    generatedKey = _generateRsaPrivateKeyPem();
  });

  /// The generated key, or null after marking the running test skipped.
  String? keyOrSkip() {
    if (generatedKey case final key?) return key;
    markTestSkipped('openssl is not on PATH, so no signing key was generated');
    return null;
  }

  // A skip is not a pass, and `dart test` exits 0 on one. Without this, a
  // runner without `openssl` on PATH — plausibly the Windows one — would go
  // green having exercised none of the transport, and nothing would say so:
  // the workflow's skip check is scoped to apps/docs.
  //
  // Locally a missing openssl stays a skip, because a red suite for a tool
  // the developer does not need is worse than a stated gap. In CI it is a
  // failure, because there the gap is invisible.
  test('the signing key was actually generated (CI: skipping is failing)', () {
    if (generatedKey != null) return;

    final ci = io.Platform.environment['CI'];
    if (ci == 'true' || ci == '1') {
      fail(
        'openssl is not on PATH, so every transport test below skipped and '
        'this job proved nothing about push delivery. Install openssl on the '
        'runner, or replace the key generation in this file.',
      );
    }

    markTestSkipped('openssl is not on PATH (not CI, so this is a gap, not a failure)');
  });

  group('access tokens', () {
    test('one token is minted for a whole batch, then reused', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final client = _FakeClient((request, _) {
        if (request.url.path.endsWith('/token')) return _tokenResponse();
        return http.Response('{}', 200);
      });

      final courier = FcmPushCourier(
        fileSystem: MemoryFileSystem(),
        client: client,
      );

      await courier.send(
        const PushMessage(title: 'a', body: 'b'),
        [for (var i = 0; i < 25; i++) 'tok-$i'],
        config: _config(privateKey: privateKey),
      );

      expect(client.sendRequests, 25);
      expect(
        client.tokenRequests,
        1,
        reason:
            'caching is required, not an optimisation: a token per send '
            'would mean 25 RSA signatures and 25 round trips before the '
            'first notification — and a hundred thousand of each at scale',
      );

      // A second batch on the same courier must not mint again.
      await courier.send(
        const PushMessage(title: 'a', body: 'b'),
        ['tok-later'],
        config: _config(privateKey: privateKey),
      );
      expect(client.tokenRequests, 1);
    });

    test('concurrent callers share one mint (single flight)', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final client = _FakeClient((request, _) => _tokenResponse());
      final cache = FcmAccessTokenCache(
        serviceAccount: ServiceAccount.fromJson(
          jsonDecode(_serviceAccountJson(privateKey: privateKey))
              as Map<String, dynamic>,
        ),
        client: client,
      );

      final tokens = await Future.wait([
        for (var i = 0; i < 8; i++) cache.get(),
      ]);

      expect(tokens, everyElement('access-token'));
      expect(
        client.tokenRequests,
        1,
        reason:
            'without single flight the first batch mints one token per '
            'in-flight send — the same bug caching was meant to fix, just '
            'narrower',
      );
    });

    test('an expired token is minted again', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final client = _FakeClient((request, _) => _tokenResponse(expiresIn: 3600));
      final serviceAccount = ServiceAccount.fromJson(
        jsonDecode(_serviceAccountJson(privateKey: privateKey))
            as Map<String, dynamic>,
      );

      final start = DateTime.utc(2026, 1, 1);
      late FcmAccessTokenCache cache;
      await withClock(Clock.fixed(start), () async {
        cache = FcmAccessTokenCache(
          serviceAccount: serviceAccount,
          client: client,
        );
        await cache.get();
        await cache.get();
      });
      expect(client.tokenRequests, 1);

      await withClock(Clock.fixed(start.add(const Duration(hours: 2))), () async {
        await cache.get();
      });
      expect(client.tokenRequests, 2);
    });

    test('a short-lived token is still cached at all', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      // 60 seconds is shorter than the 5-minute refresh margin. Subtracting
      // the margin from expiry at *read* time puts the refresh instant in the
      // past the moment the token is minted, so every call mints again — a
      // token endpoint hit once per send, reached through the code that
      // exists to prevent exactly that. Applying the margin at mint time,
      // capped at half the lifetime, is what makes a short token usable.
      final client = _FakeClient((request, _) => _tokenResponse(expiresIn: 60));
      final serviceAccount = ServiceAccount.fromJson(
        jsonDecode(_serviceAccountJson(privateKey: privateKey))
            as Map<String, dynamic>,
      );

      final start = DateTime.utc(2026, 1, 1);
      await withClock(Clock.fixed(start), () async {
        final cache = FcmAccessTokenCache(
          serviceAccount: serviceAccount,
          client: client,
        );
        await cache.get();
        await cache.get();
        await cache.get();
      });

      expect(
        client.tokenRequests,
        1,
        reason:
            'a lifetime shorter than the refresh margin must still leave '
            'something reusable, or caching degrades into no caching',
      );
    });

    test('a token is refreshed before it expires, not after', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final client = _FakeClient((request, _) => _tokenResponse(expiresIn: 3600));
      final serviceAccount = ServiceAccount.fromJson(
        jsonDecode(_serviceAccountJson(privateKey: privateKey))
            as Map<String, dynamic>,
      );

      final start = DateTime.utc(2026, 1, 1);
      late FcmAccessTokenCache cache;
      await withClock(Clock.fixed(start), () async {
        cache = FcmAccessTokenCache(
          serviceAccount: serviceAccount,
          client: client,
        );
        await cache.get();
      });
      expect(client.tokenRequests, 1);

      // 56 minutes in. The token is still valid for another four, but inside
      // the five-minute margin — a batch starting now could outlive it,
      // which is the whole reason the margin exists.
      await withClock(
        Clock.fixed(start.add(const Duration(minutes: 56))),
        () async => cache.get(),
      );
      expect(
        client.tokenRequests,
        2,
        reason:
            'refreshing exactly at expiry lets a token go stale between the '
            'check and the request landing',
      );

      // ...and not a moment earlier: at 50 minutes it is still reusable.
      final fresh = FcmAccessTokenCache(
        serviceAccount: serviceAccount,
        client: client,
      );
      await withClock(Clock.fixed(start), () async => fresh.get());
      await withClock(
        Clock.fixed(start.add(const Duration(minutes: 50))),
        () async => fresh.get(),
      );
      expect(
        client.tokenRequests,
        3,
        reason: 'a margin that swallows the whole lifetime is not a margin',
      );
    });
  });

  group('outcome classification', () {
    Future<List<PushOutcome>> sendWith(
      http.Response Function(String token) fcm, {
      required List<String> tokens,
      required String privateKey,
    }) {
      final client = _FakeClient((request, body) {
        if (request.url.path.endsWith('/token')) return _tokenResponse();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final message = decoded['message'] as Map<String, dynamic>;
        return fcm(message['token'] as String);
      });

      return FcmPushCourier(
        fileSystem: MemoryFileSystem(),
        client: client,
      ).send(
        const PushMessage(title: 'a', body: 'b'),
        tokens,
        config: _config(privateKey: privateKey),
      );
    }

    test('UNREGISTERED is permanent, and carries its token', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final outcomes = await sendWith(
        (token) => token == 'dead'
            ? _fcmError(404, 'UNREGISTERED')
            : http.Response('{}', 200),
        tokens: ['live', 'dead'],
        privateKey: privateKey,
      );

      expect(outcomes, hasLength(2));
      final dead = outcomes.firstWhere((o) => o.token == 'dead');
      expect(dead, isA<PushPermanentlyRejected>());
      expect(
        (dead as PushPermanentlyRejected).reason,
        PushRejectionReason.unregistered,
      );
      expect(outcomes.firstWhere((o) => o.token == 'live'), isA<PushDelivered>());
    });

    test('NOT_FOUND is permanent too — it is what FCM really sends', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      // Added after a live probe against real FCM, which returned
      //     HTTP 404 / error.status NOT_FOUND
      // for a well-formed token it had never issued — *not* the
      // `UNREGISTERED` the documentation leads you to, and which every test
      // here used until now.
      //
      // The stake is not cosmetic. `_classify` sends anything unrecognised
      // to the transient branch, so had this status not been handled, a dead
      // token would be retried forever and never pruned — precisely the
      // failure pruning exists to prevent, reached by following the docs
      // correctly. Nothing but a real send could have surfaced it, and this
      // test is what stops it being removed as redundant later.
      final outcomes = await sendWith(
        (token) => token == 'never-issued'
            ? _fcmError(404, 'NOT_FOUND')
            : http.Response('{}', 200),
        tokens: ['live', 'never-issued'],
        privateKey: privateKey,
      );

      final gone = outcomes.firstWhere((o) => o.token == 'never-issued');
      expect(gone, isA<PushPermanentlyRejected>());
      expect(
        (gone as PushPermanentlyRejected).reason,
        PushRejectionReason.unregistered,
        reason: 'NOT_FOUND and UNREGISTERED mean the same thing to a caller',
      );
      expect(
        outcomes.firstWhere((o) => o.token == 'live'),
        isA<PushDelivered>(),
      );
    });

    test('a missing APNs key fails one token, not the whole job', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      // Measured against live FCM on 2026-08-15, with a control in the same
      // minute: a bogus token returned 404 NOT_FOUND (so the service account
      // was demonstrably valid) while an iOS token in a project with no APNs
      // key uploaded returned this — 401, UNAUTHENTICATED, errorCode
      // THIRD_PARTY_AUTH_ERROR, "Invalid APNs credential."
      //
      // Treating that as a caller-credentials failure fails the entire job,
      // Android recipients in the same batch included, and retries forever
      // while the log blames a service account that is fine. APNs keys
      // expire and can be revoked, so this is reachable from a deployment
      // that has been working for a year.
      final outcomes = await sendWith(
        (token) => token == 'ios-token'
            ? _thirdPartyAuthError()
            : http.Response('{}', 200),
        tokens: ['android-token', 'ios-token'],
        privateKey: privateKey,
      );

      expect(
        outcomes.firstWhere((o) => o.token == 'android-token'),
        isA<PushDelivered>(),
        reason:
            'the whole point: one platform being misconfigured must not stop '
            'the other platform being notified',
      );
      expect(
        outcomes.firstWhere((o) => o.token == 'ios-token'),
        isA<PushTransientlyFailed>(),
        reason:
            'transient, never permanent. The device token is valid — it is '
            'the project that is missing a key — so pruning here would clear '
            'every iOS registration in the table over a lapsed credential, '
            'irreversibly, at exactly the moment someone is fixing it',
      );
    });

    test('a genuine credentials failure still throws', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      // The narrowness check on the test above. A 401 WITHOUT the
      // THIRD_PARTY_AUTH_ERROR detail is still about the caller, and must
      // still fail the job rather than being written off per token — that is
      // what stops a bad service account from being read as N dead devices.
      await expectLater(
        sendWith(
          (_) => _fcmError(401, 'UNAUTHENTICATED'),
          tokens: ['a', 'b'],
          privateKey: privateKey,
        ),
        throwsA(isA<PushTransportException>()),
      );
    });

    test('INVALID_ARGUMENT is permanent', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final outcomes = await sendWith(
        (_) => _fcmError(400, 'INVALID_ARGUMENT'),
        tokens: ['bad'],
        privateKey: privateKey,
      );

      expect(outcomes.single, isA<PushPermanentlyRejected>());
      expect(
        (outcomes.single as PushPermanentlyRejected).reason,
        PushRejectionReason.invalidArgument,
      );
    });

    test('quota and 5xx are transient, and distinctly so', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      for (final (status, name) in [
        (429, 'RESOURCE_EXHAUSTED'),
        (503, 'UNAVAILABLE'),
        (500, 'INTERNAL'),
      ]) {
        final outcomes = await sendWith(
          (_) => _fcmError(status, name),
          tokens: ['t'],
          privateKey: privateKey,
        );
        expect(
          outcomes.single,
          isA<PushTransientlyFailed>(),
          reason:
              '$status/$name must never prune: a token that timed out is not '
              'a token that is dead',
        );
      }
    });

    test('an unrecognised status is treated as transient', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final outcomes = await sendWith(
        (_) => _fcmError(400, 'SOMETHING_NEW'),
        tokens: ['t'],
        privateKey: privateKey,
      );

      expect(
        outcomes.single,
        isA<PushTransientlyFailed>(),
        reason:
            'guessing transient costs a retry; guessing permanent costs a '
            'device that never hears from the app again',
      );
    });

    test('bad credentials throw rather than blaming the tokens', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      await expectLater(
        sendWith(
          (_) => _fcmError(403, 'PERMISSION_DENIED'),
          tokens: ['a', 'b'],
          privateKey: privateKey,
        ),
        throwsA(isA<PushTransportException>()),
        reason:
            'classifying this per-token would prune every token in the batch '
            'over a config mistake',
      );
    });

    test('outcomes line up with the tokens given, under concurrency', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final tokens = [for (var i = 0; i < 20; i++) 'tok-$i'];
      final outcomes = await sendWith(
        (token) => token.endsWith('7')
            ? _fcmError(404, 'UNREGISTERED')
            : http.Response('{}', 200),
        tokens: tokens,
        privateKey: privateKey,
      );

      expect(
        outcomes.map((o) => o.token),
        tokens,
        reason:
            'the fan-out reconciles outcomes against the batch it read; a '
            'token that came back out of order would be miscounted, and one '
            'that vanished would be a recipient silently dropped',
      );
      expect(
        outcomes.where((o) => o is PushPermanentlyRejected).map((o) => o.token),
        ['tok-7', 'tok-17'],
      );
    });
  });

  group('message body', () {
    test('a collapse key is set for both platforms, or neither', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      late String withKey;
      late String withoutKey;

      final client = _FakeClient((request, body) {
        if (request.url.path.endsWith('/token')) return _tokenResponse();
        return http.Response('{}', 200);
      });
      final courier = FcmPushCourier(
        fileSystem: MemoryFileSystem(),
        client: client,
      );

      await courier.send(
        const PushMessage(title: 'a', body: 'b', collapseKey: 'thread-9'),
        ['t'],
        config: _config(privateKey: privateKey),
      );
      withKey = client.requests.last.body;

      await courier.send(
        const PushMessage(title: 'a', body: 'b'),
        ['t'],
        config: _config(privateKey: privateKey),
      );
      withoutKey = client.requests.last.body;

      final keyed =
          (jsonDecode(withKey) as Map)['message'] as Map<String, dynamic>;
      expect(keyed['android'], {'collapse_key': 'thread-9'});
      expect(keyed['apns'], {
        'headers': {'apns-collapse-id': 'thread-9'},
      });

      final bare =
          (jsonDecode(withoutKey) as Map)['message'] as Map<String, dynamic>;
      expect(
        bare.containsKey('android') || bare.containsKey('apns'),
        isFalse,
        reason:
            'setting only one platform leaves duplicates visible on the '
            'other, which is worse than setting neither',
      );
    });

    test('data values travel as strings', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final client = _FakeClient((request, _) {
        if (request.url.path.endsWith('/token')) return _tokenResponse();
        return http.Response('{}', 200);
      });

      await FcmPushCourier(
        fileSystem: MemoryFileSystem(),
        client: client,
      ).send(
        const PushMessage(
          title: 'a',
          body: 'b',
          data: {'lossEventId': 'evt_1', 'causedById': 'usr_2'},
        ),
        ['t'],
        config: _config(privateKey: privateKey),
      );

      final message =
          (jsonDecode(client.requests.last.body) as Map)['message']
              as Map<String, dynamic>;
      expect(message['data'], {
        'lossEventId': 'evt_1',
        'causedById': 'usr_2',
      });
    });
  });

  group('credentials', () {
    test('a missing key file names the file rather than the exception', () {
      final courier = FcmPushCourier(fileSystem: MemoryFileSystem());

      expect(
        () => courier.send(
          const PushMessage(title: 'a', body: 'b'),
          ['t'],
          config: PushConfig(
            projectId: 'p',
            credentials: const PushCredentials.file('/keys/absent.json'),
          ),
        ),
        throwsA(
          isA<PushTransportException>().having(
            (e) => e.message,
            'message',
            contains('/keys/absent.json'),
          ),
        ),
      );
    });

    test('a key file is read from disk at runtime', () async {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      final fs = MemoryFileSystem();
      fs.file('/keys/sa.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(_serviceAccountJson(privateKey: privateKey));

      final client = _FakeClient((request, _) {
        if (request.url.path.endsWith('/token')) return _tokenResponse();
        return http.Response('{}', 200);
      });

      final outcomes = await FcmPushCourier(
        fileSystem: fs,
        client: client,
      ).send(
        const PushMessage(title: 'a', body: 'b'),
        ['t'],
        config: PushConfig(
          projectId: 'fixture-project',
          credentials: const PushCredentials.file('/keys/sa.json'),
        ),
      );

      expect(outcomes.single, isA<PushDelivered>());
    });

    test('a private key never appears in an error message', () {
      final privateKey = keyOrSkip();
      if (privateKey == null) return;

      expect(
        () => ServiceAccount.fromJson(
          jsonDecode(_serviceAccountJson(privateKey: 'not-a-pem'))
              as Map<String, dynamic>,
        ),
        returnsNormally,
        reason: 'parsing is deferred to signing time',
      );

      // The signing path is where a naive implementation echoes the key it
      // could not parse.
      final cache = FcmAccessTokenCache(
        serviceAccount: ServiceAccount.fromJson(
          jsonDecode(_serviceAccountJson(privateKey: 'not-a-pem'))
              as Map<String, dynamic>,
        ),
        client: _FakeClient((_, _) => _tokenResponse()),
      );

      expect(
        cache.get(),
        throwsA(
          isA<PushTransportException>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains('not-a-pem')),
          ),
        ),
      );
    });
  });
}
