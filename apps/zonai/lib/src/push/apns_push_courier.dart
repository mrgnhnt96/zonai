import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:http2/http2.dart';
import 'package:zonai/src/push/apns_provider_token.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// APNs, spoken directly — no Firebase in the path.
///
/// **Why HTTP/2 rather than the `http` package.** Apple requires it, and not
/// as a formality: one connection multiplexes many concurrent sends, and the
/// documented way to hit the rate limits is to open a connection per
/// notification. So this holds a connection open and streams requests over
/// it, which is a different shape from [FcmPushCourier]'s bounded pool of
/// independent POSTs — and the reason `PushCourier` was an interface.
///
/// **What it does not do.** Reconnect on its own beyond the current batch,
/// or keep the connection alive between fan-outs. A batch opens, sends,
/// closes. That gives up some of HTTP/2's benefit and buys a courier with no
/// background state to leak, which matters more while this is new: a
/// connection held across a job that crashed is the kind of thing that
/// surfaces days later as a socket exhaustion nobody can place.
class ApnsPushCourier implements PushCourier {
  ApnsPushCourier({
    required this.fileSystem,
    Future<ClientTransportConnection> Function(ApnsConfig config)? connect,
  }) : _connect = connect ?? _connectOverTls;

  final FileSystem fileSystem;
  final Future<ClientTransportConnection> Function(ApnsConfig config) _connect;

  /// Keyed by key id, because the cached token is bound to the key that
  /// signed it. A flavour switch mid-process must not reuse the last one.
  final Map<String, ApnsProviderToken> _tokens = {};

  static Future<ClientTransportConnection> _connectOverTls(
    ApnsConfig config,
  ) async {
    // ALPN is not optional here: APNs speaks HTTP/2 only, and a connection
    // that negotiated http/1.1 is refused rather than downgraded.
    final socket = await SecureSocket.connect(
      config.host,
      443,
      supportedProtocols: const ['h2'],
    );
    return ClientTransportConnection.viaSocket(socket);
  }

  @override
  Future<List<PushOutcome>> send(
    PushMessage message,
    List<String> tokens, {
    required PushConfig config,
  }) async {
    if (tokens.isEmpty) return const [];

    final apns = config.apns;
    if (apns == null) {
      throw PushTransportException(
        'ApnsPushCourier was asked to send with no AppConfig.push.apns set',
      );
    }

    final providerToken = _providerTokenFor(apns).get();
    final body = utf8.encode(jsonEncode(_payload(message)));

    final ClientTransportConnection connection;
    try {
      connection = await _connect(apns);
    } catch (e) {
      // Reaching Apple at all is not this token's fault, so every recipient
      // in the batch is transient rather than the job failing: the next drain
      // retries from the same cursor.
      return [
        for (final token in tokens)
          PushTransientlyFailed(
            token: token,
            detail: 'could not connect to ${apns.host}: $e',
          ),
      ];
    }

    try {
      // Concurrent over one connection, which is the whole point of HTTP/2 —
      // still bounded, because Apple's per-connection stream limit is not
      // infinite and an unbounded fan-out meets it as an error rather than as
      // backpressure.
      final outcomes = List<PushOutcome?>.filled(tokens.length, null);
      var next = 0;

      Future<void> worker() async {
        while (true) {
          final index = next++;
          if (index >= tokens.length) return;
          outcomes[index] = await _sendOne(
            connection: connection,
            apns: apns,
            providerToken: providerToken,
            message: message,
            body: body,
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
    } finally {
      await connection.finish();
    }
  }

  Future<PushOutcome> _sendOne({
    required ClientTransportConnection connection,
    required ApnsConfig apns,
    required String providerToken,
    required PushMessage message,
    required List<int> body,
    required String token,
  }) async {
    final headers = <Header>[
      Header.ascii(':method', 'POST'),
      Header.ascii(':scheme', 'https'),
      Header.ascii(':authority', apns.host),
      Header.ascii(':path', '/3/device/$token'),
      Header.ascii('authorization', 'bearer $providerToken'),
      // One key can serve every app on a team, so the topic is the only thing
      // saying which app this is for. APNs refuses a send without it.
      Header.ascii('apns-topic', apns.bundleId),
      // `alert` rather than `background`: a wrong push type is rejected on
      // iOS 13+, and a fan-out sends user-visible notifications by definition.
      Header.ascii('apns-push-type', 'alert'),
      Header.ascii('apns-priority', '10'),
      if (message.collapseKey case final key?)
        Header.ascii('apns-collapse-id', key),
    ];

    try {
      final stream = connection.makeRequest(headers, endStream: false)
        ..outgoingMessages.add(DataStreamMessage(body, endStream: true));
      await stream.outgoingMessages.close();

      var status = 0;
      final responseBody = StringBuffer();
      await for (final incoming in stream.incomingMessages) {
        switch (incoming) {
          case HeadersStreamMessage(:final headers):
            for (final header in headers) {
              if (ascii.decode(header.name) == ':status') {
                status = int.tryParse(ascii.decode(header.value)) ?? 0;
              }
            }
          case DataStreamMessage(:final bytes):
            responseBody.write(utf8.decode(bytes, allowMalformed: true));
        }
      }

      return _classify(status, '$responseBody', token);
    } on SocketException catch (e) {
      return PushTransientlyFailed(
        token: token,
        detail: 'network: ${e.message}',
      );
    } on TimeoutException {
      return PushTransientlyFailed(token: token, detail: 'timeout');
    } on StateError catch (e) {
      // The connection died mid-stream. Transient for the same reason a
      // failed connect is: nothing about this token caused it.
      return PushTransientlyFailed(
        token: token,
        detail: 'stream: ${e.message}',
      );
    }
  }

  /// Maps one APNs response onto the three outcomes.
  ///
  /// Apple puts the meaning in a `reason` string rather than in the status,
  /// and the same status carries both kinds of problem — `403` is a bad
  /// provider token *and* a wrong topic, `400` is a malformed token *and* a
  /// malformed payload. So the reason is what is read, and the status is only
  /// the fallback.
  ///
  /// **These mappings come from Apple's documentation and have not all been
  /// observed.** The FCM table in `fcm_push_courier.dart` was written the same
  /// way and turned out to be wrong three times, each time in the direction
  /// that silently disabled pruning. Anything not recognised here is treated
  /// as transient on purpose: an unknown reason costs a retry, and guessing
  /// permanent costs a device that never hears from the app again.
  PushOutcome _classify(int status, String body, String token) {
    if (status == 200) return PushDelivered(token: token);

    final reason = _reason(body);

    return switch (reason) {
      // The device token is not, and will never be, valid for this app.
      // `BadDeviceToken` is carried through verbatim for a reason: it is the
      // symptom of a sandbox/production mismatch, where the token is valid and
      // the environment is wrong. Reported as bare "unregistered" it reads as
      // "this device is gone", and the operator goes looking at the device.
      'BadDeviceToken' || 'Unregistered' => PushPermanentlyRejected(
        token: token,
        reason: PushRejectionReason.unregistered,
        detail: '$status $reason',
      ),

      // Looks per-token and is not. Measured live on 2026-08-15: with one
      // key and one device token, a topic the team does not own answers
      // `TopicDisallowed`, while a topic it *does* own — but which the token
      // was not issued for — answers this. So it is produced by a `bundleId`
      // that disagrees with the app, which is a config fault and a **uniform**
      // one: point `ApnsConfig` at the wrong bundle and every iOS recipient
      // comes back this way, so a permanent reading would prune every iOS
      // registration in the table in a single drain.
      //
      // Transient instead, and it self-corrects the moment the config is
      // right. Same shape as FCM's `THIRD_PARTY_AUTH_ERROR`: a per-caller
      // problem wearing per-token clothing.
      'DeviceTokenNotForTopic' => PushTransientlyFailed(
        token: token,
        detail:
            '$status DeviceTokenNotForTopic — this token was issued for a '
            'different app. Check ApnsConfig.bundleId against the app that '
            'registered it; nothing is wrong with the device.',
      ),

      // The notification itself is wrong, not the device.
      'PayloadEmpty' ||
      'PayloadTooLarge' ||
      'BadCollapseId' ||
      'BadPriority' ||
      'MissingTopic' ||
      'TopicDisallowed' => PushPermanentlyRejected(
        token: token,
        reason: PushRejectionReason.invalidArgument,
        detail: '$status $reason',
      ),

      // About the caller, never about one token — so the job fails and the
      // cursor stays put, rather than pruning a table's worth of valid
      // registrations over an expired key. Same reasoning as FCM's 401/403.
      'BadJwtToken' ||
      'ExpiredProviderToken' ||
      'InvalidProviderToken' ||
      'MissingProviderToken' ||
      'ExpiredToken' => throw PushTransportException(
        'APNs rejected the provider token ($status $reason). Check the '
        'key id, team id and that the .p8 matches them.',
      ),

      // Explicitly transient, and named so the log says which.
      'TooManyProviderTokenUpdates' => PushTransientlyFailed(
        token: token,
        detail:
            '$status TooManyProviderTokenUpdates — provider tokens were '
            'regenerated faster than once per 20 minutes',
      ),
      'TooManyRequests' ||
      'ServiceUnavailable' ||
      'InternalServerError' ||
      'IdleTimeout' ||
      'Shutdown' => PushTransientlyFailed(
        token: token,
        detail: '$status $reason',
      ),

      final other => PushTransientlyFailed(
        token: token,
        detail: '$status ${other ?? 'unknown'}',
      ),
    };
  }

  /// APNs' `reason`, or null when the body is not the shape we expect.
  String? _reason(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return decoded['reason'] as String?;
    } on FormatException {
      return null;
    }
  }

  /// The APNs payload.
  ///
  /// `data` is merged at the top level beside `aps`, which is where APNs
  /// expects custom keys — unlike FCM, which nests them under `data`. An app
  /// reading the two transports therefore sees the same keys either way.
  Map<String, dynamic> _payload(PushMessage message) => {
    'aps': {
      'alert': {'title': message.title, 'body': message.body},
    },
    ...message.data,
  };

  ApnsProviderToken _providerTokenFor(ApnsConfig config) {
    return _tokens[config.keyId] ??= ApnsProviderToken(
      privateKeyPem: _readKey(config.credentials),
      keyId: config.keyId,
      teamId: config.teamId,
    );
  }

  String _readKey(ApnsCredentials credentials) {
    return switch (credentials) {
      ApnsCredentialsInline(:final pem) => pem,
      ApnsCredentialsFile(:final path) => _readKeyFile(path),
    };
  }

  String _readKeyFile(String path) {
    final file = fileSystem.file(path);
    if (!file.existsSync()) {
      throw PushTransportException(
        'APNs auth key not found: $path. This is the recommended production '
        'form precisely because the key lives outside the binary — check the '
        'deploy step that places it.',
      );
    }
    return file.readAsStringSync();
  }

  @override
  Future<void> close() async => _tokens.clear();
}
