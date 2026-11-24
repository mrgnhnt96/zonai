import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:http/http.dart' as http;
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai/src/push/web_push_crypto.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Standard Web Push — RFC 8030 delivery, RFC 8291 payload encryption,
/// RFC 8292 VAPID — to browsers and installed PWAs. No Firebase.
///
/// Each "token" is a browser's `PushSubscription.toJSON()`: the push service
/// URL to POST to, and the keys to encrypt to. So unlike FCM and APNs there is
/// no one host; every subscription names its own (Chrome's, Mozilla's,
/// Apple's), and the VAPID JWT is minted per push-service origin.
class WebPushCourier implements PushCourier {
  WebPushCourier({required this.fileSystem, http.Client? client})
    : _client = client ?? http.Client();

  final FileSystem fileSystem;
  final http.Client _client;

  /// How long a push service holds a message for an offline browser.
  ///
  /// A day, because these are reminders and summaries: one that arrives two
  /// days late is noise. The header is mandatory, and a push service that
  /// gets `0` may drop the message the moment the browser is not connected.
  static const ttlSeconds = 86400;

  /// Keyed by public key, because the cached JWTs are bound to the key that
  /// signed them. A flavour switch mid-process must not reuse the last one.
  final Map<String, VapidSigner> _signers = {};

  @override
  Future<List<PushOutcome>> send(
    PushMessage message,
    List<String> tokens, {
    required PushConfig config,
  }) async {
    if (tokens.isEmpty) return const [];

    final webPush = config.webPush;
    if (webPush == null) {
      throw PushTransportException(
        'WebPushCourier was asked to send with no AppConfig.push.webPush set',
      );
    }

    final signer = _signerFor(webPush);
    final plaintext = utf8.encode(jsonEncode(payloadFor(message)));
    if (plaintext.length > maxWebPushPlaintextBytes) {
      // The enqueue-time size check keeps a message well under this, so
      // reaching here means the two budgets drifted. The same for every
      // recipient, and the message's fault rather than any device's.
      return [
        for (final token in tokens)
          PushTransientlyFailed(
            token: token,
            detail:
                'payload is ${plaintext.length} bytes; one Web Push record '
                'carries at most $maxWebPushPlaintextBytes',
          ),
      ];
    }

    // Same bounded pool as FCM: every subscription is its own POST, and a
    // batch fired at once meets a push service's rate limit rather than
    // backpressure.
    final outcomes = List<PushOutcome?>.filled(tokens.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= tokens.length) return;
        outcomes[index] = await _sendOne(
          signer: signer,
          message: message,
          plaintext: plaintext,
          token: tokens[index],
        );
      }
    }

    await Future.wait([
      for (var i = 0; i < config.concurrency && i < tokens.length; i++)
        worker(),
    ]);

    return [
      for (var i = 0; i < tokens.length; i++)
        outcomes[i] ??
            PushTransientlyFailed(
              token: tokens[i],
              detail: 'no outcome recorded',
            ),
    ];
  }

  /// What the app's service worker receives in its `push` event, as JSON.
  ///
  /// `tag` is the collapse key because that is what `showNotification`
  /// replaces on: the service worker passes it straight through, and a
  /// re-sent notification takes the place of the first rather than stacking.
  static Map<String, dynamic> payloadFor(PushMessage message) => {
    'title': message.title,
    'body': message.body,
    'tag': ?message.collapseKey,
    'data': message.data,
  };

  Future<PushOutcome> _sendOne({
    required VapidSigner signer,
    required PushMessage message,
    required List<int> plaintext,
    required String token,
  }) async {
    final WebPushSubscription subscription;
    try {
      subscription = WebPushSubscription.parse(token);
    } on FormatException catch (e) {
      // This row's problem and nobody else's. Not a prune: the specification
      // only lets the push service say a subscription is gone, and a value
      // that never parsed may be a client storing the wrong thing — fixed by
      // the app's next registration, not by deleting the row.
      return PushTransientlyFailed(
        token: token,
        detail: 'not a Web Push subscription: ${e.message}',
      );
    }

    final body = encryptWebPushPayload(
      plaintext: plaintext,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
    );

    final http.Response response;
    try {
      response = await _client.post(
        subscription.endpoint,
        headers: {
          'Authorization': signer.authorizationFor(subscription.endpoint),
          'Content-Encoding': 'aes128gcm',
          'Content-Type': 'application/octet-stream',
          'TTL': '$ttlSeconds',
          'Urgency': 'high',
          if (webPushTopic(message.collapseKey) case final topic?)
            'Topic': topic,
        },
        body: body,
      );
    } on SocketException catch (e) {
      return PushTransientlyFailed(
        token: token,
        detail: 'network: ${e.osError?.message ?? e.message}',
      );
    } on http.ClientException catch (e) {
      return PushTransientlyFailed(token: token, detail: 'http: ${e.message}');
    } on TimeoutException {
      return PushTransientlyFailed(token: token, detail: 'timeout');
    }

    return _classify(response, token, subscription.endpoint);
  }

  /// Maps one push service response onto the three outcomes.
  ///
  /// Only 404 and 410 prune. RFC 8030 gives those to a subscription that no
  /// longer exists — the user revoked permission, the browser profile is gone
  /// — and every push service uses them that way.
  ///
  /// 401 and 403 are VAPID failures, and are **not** thrown as a job-level
  /// fault the way FCM's are. A push service answers 403 to a subscription
  /// made under a *different* VAPID key, which is per-row: after a key
  /// rotation, one stale subscription would otherwise fail the whole job on
  /// every drain and stall everyone behind it. Transient keeps both cases
  /// safe — a wholly wrong key fails every row loudly without pruning any.
  PushOutcome _classify(http.Response response, String token, Uri endpoint) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return PushDelivered(token: token);

    final host = endpoint.host;
    final detail = _bodyExcerpt(response);

    return switch (status) {
      404 || 410 => PushPermanentlyRejected(
        token: token,
        reason: PushRejectionReason.unregistered,
        detail: '$status from $host — the subscription is gone$detail',
      ),
      401 || 403 => PushTransientlyFailed(
        token: token,
        detail:
            '$status from $host — VAPID was refused. Either '
            'AppConfig.push.webPush has the wrong key pair or subject, or this '
            'subscription was made with a different applicationServerKey and '
            'the app must subscribe again$detail',
      ),
      413 => PushTransientlyFailed(
        token: token,
        detail: '413 from $host — the encrypted payload is too large$detail',
      ),
      _ => PushTransientlyFailed(
        token: token,
        detail: '$status from $host$detail',
      ),
    };
  }

  /// The start of a push service's error body, for the job's failure detail.
  String _bodyExcerpt(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return '';
    return ': ${body.length > 200 ? '${body.substring(0, 200)}…' : body}';
  }

  VapidSigner _signerFor(WebPushConfig config) {
    return _signers[config.publicKey] ??= _buildSigner(config);
  }

  VapidSigner _buildSigner(WebPushConfig config) {
    final privateKey = switch (config.privateKey) {
      WebPushPrivateKeyInline(:final key) => key,
      WebPushPrivateKeyFile(:final path) => _readKeyFile(path),
    };
    try {
      return VapidSigner.fromKeys(
        publicKey: config.publicKey,
        privateKey: privateKey,
        subject: config.subject,
      );
    } on FormatException catch (e) {
      // About the server, never one subscription — so the job fails and the
      // cursor stays put, like a bad APNs key.
      throw PushTransportException(
        'AppConfig.push.webPush is unusable: ${e.message}',
      );
    }
  }

  String _readKeyFile(String path) {
    final file = fileSystem.file(path);
    if (!file.existsSync()) {
      throw PushTransportException(
        'Web Push VAPID private key not found: $path. This is the recommended '
        'production form precisely because the key lives outside the binary '
        '— check the deploy step that places it.',
      );
    }
    return file.readAsStringSync();
  }

  @override
  Future<void> close() async {
    _client.close();
    _signers.clear();
  }
}
