import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:http/http.dart' as http;
import 'package:zonai/src/push/fcm_access_token.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// FCM HTTP v1: service-account JWT → OAuth2 access token →
/// `POST /v1/projects/{projectId}/messages:send`.
///
/// The legacy endpoint is not implemented and will not be: it is retired, and
/// supporting both would double the error-classification surface that
/// [_classify] exists to get right.
class FcmPushCourier implements PushCourier {
  FcmPushCourier({
    required this.fileSystem,
    http.Client? client,
    String baseUri = defaultBaseUri,
  }) : _client = client ?? http.Client(),
       // A trailing slash would produce `//v1/...`, which FCM 404s. Cheaper
       // to absorb here than to make every caller spell it exactly right.
       _baseUri = baseUri.endsWith('/')
           ? baseUri.substring(0, baseUri.length - 1)
           : baseUri;

  static const defaultBaseUri = 'https://fcm.googleapis.com';

  final FileSystem fileSystem;
  final http.Client _client;

  /// Where `messages:send` lives.
  ///
  /// Overridable because FCM has no sandbox. There is no address you can
  /// point this at that accepts a send and does not deliver it to a real
  /// device, so the only way to exercise the transport against a real socket
  /// — real TCP, real headers, a real signed assertion someone else verifies
  /// — is to stand up something local that speaks the same protocol.
  ///
  /// Deliberately a constructor argument rather than a [PushConfig] field:
  /// config is parsed from user-supplied yaml, and an endpoint override there
  /// would be a way to redirect production's notifications, access token and
  /// all, by editing a config file.
  final String _baseUri;

  /// Keyed by project id, because the cached token is scoped to the service
  /// account that minted it. A flavor switch mid-process must not reuse the
  /// previous project's token.
  final Map<String, FcmAccessTokenCache> _tokens = {};

  @override
  Future<List<PushOutcome>> send(
    PushMessage message,
    List<String> tokens, {
    required PushConfig config,
  }) async {
    if (tokens.isEmpty) return const [];

    final accessToken = await _accessTokenFor(config).get();
    final endpoint = Uri.parse(
      '$_baseUri/v1/projects/${config.projectId}/messages:send',
    );

    // A bounded pool, not `Future.wait` over every token: FCM enforces
    // per-project quotas, and a batch of 500 fired at once is the reliable
    // way to meet them. `outcomes` is pre-sized and written by index so the
    // result lines up with `tokens` regardless of completion order — the
    // contract [PushCourier.send] promises.
    final outcomes = List<PushOutcome?>.filled(tokens.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= tokens.length) return;
        outcomes[index] = await _sendOne(
          endpoint: endpoint,
          accessToken: accessToken,
          message: message,
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

  Future<PushOutcome> _sendOne({
    required Uri endpoint,
    required String accessToken,
    required PushMessage message,
    required String token,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        endpoint,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'message': _messageBody(message, token)}),
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

    return _classify(response, token);
  }

  /// Maps one HTTP response onto the three outcomes.
  ///
  /// Only [PushPermanentlyRejected] prunes, so the boundary drawn here is
  /// the boundary between "clear this row" and "try again later" — the one
  /// distinction the whole feature exists to make on the app's behalf.
  PushOutcome _classify(http.Response response, String token) {
    if (response.statusCode == 200) {
      return PushDelivered(token: token);
    }

    final status = _errorStatus(response.body);

    // A 401 that is about the *platform's* credentials rather than ours.
    //
    // Observed live on 2026-08-15 with a control in the same minute: a bogus
    // token returned `404 NOT_FOUND` — so the service account was
    // demonstrably valid — while an iOS token in a project with no APNs key
    // uploaded returned `401 UNAUTHENTICATED`, "Invalid APNs credential.",
    // `errorCode: THIRD_PARTY_AUTH_ERROR`.
    //
    // Throwing here would fail the whole job over one misconfigured
    // platform, taking every Android recipient in the batch down with it,
    // and retry forever while the log blamed a service account that is fine.
    // APNs keys expire and can be revoked, so a deployment that has worked
    // for a year can arrive here overnight.
    //
    // Transient rather than permanent, and that distinction is the important
    // one: the device token is perfectly valid — it is the project that is
    // missing a key — so pruning would clear every iOS registration in the
    // table over a lapsed credential, irreversibly, at exactly the moment
    // someone is fixing it.
    if (_errorCode(response.body) == 'THIRD_PARTY_AUTH_ERROR') {
      return PushTransientlyFailed(
        token: token,
        detail:
            '${response.statusCode} THIRD_PARTY_AUTH_ERROR — the APNs key '
            'for this project is missing, expired or revoked. Nothing is '
            'wrong with this device token.',
      );
    }

    // Not about this token at all: the credentials are wrong or lack the
    // scope. Throwing fails the whole job and leaves the cursor where it is.
    // Classifying it per-token would prune every token in the batch over a
    // config mistake — the most expensive possible misreading.
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw PushTransportException(
        'FCM rejected the credentials (${response.statusCode}): '
        '${status ?? response.body}',
      );
    }

    return switch (status) {
      'UNREGISTERED' || 'NOT_FOUND' => PushPermanentlyRejected(
        token: token,
        reason: PushRejectionReason.unregistered,
        detail: '${response.statusCode} $status',
      ),
      'INVALID_ARGUMENT' => PushPermanentlyRejected(
        token: token,
        reason: PushRejectionReason.invalidArgument,
        detail: '${response.statusCode} $status',
      ),
      // UNAVAILABLE, INTERNAL, RESOURCE_EXHAUSTED (quota), and anything
      // unrecognised. Unrecognised lands here on purpose: an unknown status
      // treated as transient costs a retry, and treated as permanent costs a
      // device that never hears from the app again.
      final other => PushTransientlyFailed(
        token: token,
        detail: '${response.statusCode} ${other ?? 'unknown'}',
      ),
    };
  }

  /// FCM's `error.details[].errorCode`, or null when absent.
  ///
  /// Separate from [_errorStatus] because the two carry different things: a
  /// bad APNs key and a bad service account are both `UNAUTHENTICATED`, and
  /// only this tells them apart. One is a per-token problem and the other
  /// fails the job, so reading the wrong field is the difference between a
  /// misconfigured platform and a stalled queue.
  String? _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      if (error is! Map) return null;
      final details = error['details'];
      if (details is! List) return null;
      for (final detail in details) {
        if (detail is Map && detail['errorCode'] is String) {
          return detail['errorCode'] as String;
        }
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  /// FCM's `error.status`, or null when the body is not the shape we expect.
  String? _errorStatus(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      if (error is! Map) return null;
      return error['status'] as String?;
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> _messageBody(PushMessage message, String token) {
    return {
      'token': token,
      'notification': {'title': message.title, 'body': message.body},
      if (message.data.isNotEmpty) 'data': message.data,
      if (message.collapseKey case final key?) ...{
        // The same intent, spelled differently per platform: Android
        // collapses on `collapse_key`, APNs on the `apns-collapse-id`
        // header. Setting only one leaves duplicates visible on the other.
        'android': {'collapse_key': key},
        'apns': {
          'headers': {'apns-collapse-id': key},
        },
      },
    };
  }

  FcmAccessTokenCache _accessTokenFor(PushConfig config) {
    // Both halves are nullable because an iOS-only app talking to APNs
    // directly has no Firebase project at all. Reaching here without them
    // means the engine routed a recipient to the wrong courier, so the
    // message names that rather than reporting a missing field.
    final projectId = config.projectId;
    final credentials = config.credentials;
    if (projectId == null || credentials == null) {
      throw PushTransportException(
        'FcmPushCourier was asked to send with no FCM configuration '
        '(AppConfig.push.projectId and .credentials). An Android recipient '
        'cannot be delivered without it; an iOS one should have been routed '
        'to APNs.',
      );
    }

    return _tokens[projectId] ??= FcmAccessTokenCache(
      serviceAccount: _serviceAccount(credentials),
      client: _client,
    );
  }

  ServiceAccount _serviceAccount(PushCredentials credentials) {
    final raw = switch (credentials) {
      PushCredentialsInline(:final json) => json,
      PushCredentialsFile(:final path) => _readKeyFile(path),
    };

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      throw PushTransportException(
        'Push credentials are not valid service-account JSON '
        '(${e.runtimeType})',
      );
    }

    return ServiceAccount.fromJson(decoded);
  }

  String _readKeyFile(String path) {
    final file = fileSystem.file(path);
    if (!file.existsSync()) {
      throw PushTransportException(
        'Push credentials file not found: $path. This is the recommended '
        'production form precisely because the key lives outside the binary '
        '— check the deploy step that places it.',
      );
    }
    return file.readAsStringSync();
  }

  @override
  Future<void> close() async {
    _client.close();
    _tokens.clear();
  }
}
