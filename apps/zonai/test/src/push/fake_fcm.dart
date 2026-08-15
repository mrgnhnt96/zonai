/// A real HTTP server that speaks FCM HTTP v1 back at us.
///
/// Shared by the two tests that need a transport which is *not* a stubbed
/// `http.Client`: the wire test, which checks the protocol, and the
/// end-to-end test, which drives the whole engine through it. FCM has no
/// sandbox — every address Google publishes delivers to a real device — so
/// something local that verifies signatures and returns FCM's own error
/// shapes is the only way either of those runs at all.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:jose/jose.dart';

/// Generates an RSA keypair with `openssl`, returning both PEMs.
///
/// Split into two keys on purpose. The private one signs, the public one —
/// and only the public one — reaches [FakeFcm], so verification there is the
/// real asymmetric check rather than a round trip through one object that
/// would pass even if we signed with the wrong key entirely.
///
/// Returns null when `openssl` is not on PATH; callers skip rather than fail.
({String private, String public})? generateKeypair() {
  final dir = io.Directory.systemTemp.createTempSync('zonai_fcm');
  try {
    final privatePath = '${dir.path}/private.pem';
    final publicPath = '${dir.path}/public.pem';

    final gen = io.Process.runSync('openssl', [
      'genpkey',
      '-algorithm',
      'RSA',
      '-pkeyopt',
      'rsa_keygen_bits:2048',
      '-out',
      privatePath,
    ]);
    if (gen.exitCode != 0) return null;

    final pub = io.Process.runSync('openssl', [
      'rsa',
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

/// What [FakeFcm] decided to answer for one recipient token.
typedef SendReply = ({int status, String? errorStatus});

/// Delivered.
const okReply = (status: 200, errorStatus: null);

/// One of FCM's documented error statuses, with the HTTP code it arrives on.
SendReply errReply(int status, String errorStatus) =>
    (status: status, errorStatus: errorStatus);

/// The two endpoints FCM v1 needs, implemented for real and checking its side
/// of the contract rather than rubber-stamping it.
class FakeFcm {
  FakeFcm._(this._server, this._publicKeyStore);

  static Future<FakeFcm> start({required String publicKeyPem}) async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    final store = JsonWebKeyStore()..addKey(JsonWebKey.fromPem(publicKeyPem));
    final fake = FakeFcm._(server, store);
    unawaited(fake._serve());
    return fake;
  }

  final io.HttpServer _server;
  final JsonWebKeyStore _publicKeyStore;

  String get baseUri => 'http://127.0.0.1:${_server.port}';
  String get tokenUri => '$baseUri/token';

  /// The access token this server hands out.
  var issuedAccessToken = 'issued-access-token';

  /// The access token `messages:send` will accept, when it differs from the
  /// one handed out. Setting it is how a rotated or wrongly-scoped
  /// credential is reproduced: the exchange succeeds and every send comes
  /// back 401, which is the shape that must not be read as "these devices are
  /// dead".
  String? acceptedAccessToken;

  /// Set to fail the token exchange, the way Google does for a bad key.
  bool rejectAssertion = false;

  /// Decides the reply for one recipient token. Defaults to delivering.
  SendReply Function(String token) replyFor = (_) => okReply;

  /// Every verified assertion payload, in arrival order. A request that fails
  /// verification never lands here — which is what makes an empty list after a
  /// send a failure rather than an oddity.
  final verifiedAssertions = <Map<String, dynamic>>[];

  /// Why verification failed, if it did. Surfaced so a test reports the real
  /// reason instead of a bare "expected 1, got 0".
  String? assertionRejection;

  final tokenRequests = <String>[];
  final sends = <({String path, String? authorization, Map body})>[];

  /// The recipient token of every send that arrived, in arrival order.
  List<String> get sentTokens => [
    for (final send in sends) (send.body['message'] as Map)['token'] as String,
  ];

  Future<void> _serve() async {
    await for (final request in _server) {
      try {
        await _route(request);
      } catch (e) {
        request.response.statusCode = 500;
        request.response.write('fake fcm blew up: $e');
        await request.response.close();
      }
    }
  }

  Future<void> _route(io.HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();

    if (request.uri.path == '/token') {
      return _token(request, body);
    }
    if (request.uri.path.endsWith('messages:send')) {
      return _send(request, body);
    }

    request.response.statusCode = 404;
    await request.response.close();
  }

  Future<void> _token(io.HttpRequest request, String body) async {
    tokenRequests.add(body);

    final form = Uri.splitQueryString(body);
    final assertion = form['assertion'];

    if (assertion == null) {
      assertionRejection = 'no assertion in the form body';
      return _json(request, 400, {'error': 'invalid_request'});
    }

    // The actual check. Google holds only the public half of the service
    // account key, so this is the same verification our assertion has to pass
    // in production, performed by code that cannot have been handed the
    // signing key by accident.
    try {
      final jws = JsonWebSignature.fromCompactSerialization(assertion);
      final payload = await jws.getPayload(_publicKeyStore);
      verifiedAssertions.add(
        Map<String, dynamic>.from(payload.jsonContent as Map),
      );
    } catch (e) {
      assertionRejection = 'signature did not verify: $e';
      return _json(request, 400, {'error': 'invalid_grant'});
    }

    if (rejectAssertion) {
      return _json(request, 400, {
        'error': 'invalid_grant',
        'error_description': 'Invalid JWT Signature.',
      });
    }

    return _json(request, 200, {
      'access_token': issuedAccessToken,
      'expires_in': 3600,
      'token_type': 'Bearer',
    });
  }

  Future<void> _send(io.HttpRequest request, String body) async {
    final authorization = request.headers.value('authorization');
    final decoded = jsonDecode(body) as Map<String, dynamic>;

    sends.add((
      path: request.uri.path,
      authorization: authorization,
      body: decoded,
    ));

    if (authorization != 'Bearer ${acceptedAccessToken ?? issuedAccessToken}') {
      return _json(request, 401, {
        'error': {
          'code': 401,
          'status': 'UNAUTHENTICATED',
          'message': 'Request had invalid authentication credentials.',
        },
      });
    }

    final message = decoded['message'] as Map<String, dynamic>;
    final reply = replyFor(message['token'] as String);

    if (reply.errorStatus case final status?) {
      return _json(request, reply.status, {
        'error': {'code': reply.status, 'status': status, 'message': status},
      });
    }

    return _json(request, 200, {'name': 'projects/p/messages/1'});
  }

  Future<void> _json(io.HttpRequest request, int status, Object body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = io.ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

/// A service-account key file whose `token_uri` points at [tokenUri], which is
/// what lets the courier's OAuth2 exchange reach a local server unmodified.
String serviceAccountJson({
  required String privateKey,
  required String tokenUri,
  String projectId = 'wire-project',
}) => jsonEncode({
  'type': 'service_account',
  'project_id': projectId,
  'client_email': 'wire@$projectId.iam.gserviceaccount.com',
  'private_key': privateKey,
  'token_uri': tokenUri,
});
