/// A real HTTP/2 server that speaks APNs back at us.
///
/// Necessarily a *real* server rather than a stubbed client: APNs is HTTP/2
/// only, the courier holds one connection and multiplexes over it, and none
/// of that shape survives being replaced by a function that returns canned
/// responses. Running it over a plain socket rather than TLS keeps the test
/// hermetic — what is under test is the protocol and the classification, not
/// Dart's TLS.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:http2/http2.dart';

/// What [FakeApns] answers for one device token.
typedef ApnsReply = ({int status, String? reason});

/// Accepted.
const apnsOk = (status: 200, reason: null);

/// One of Apple's documented `reason` strings, with the status it arrives on.
ApnsReply apnsError(int status, String reason) =>
    (status: status, reason: reason);

/// One request as the server saw it.
typedef ApnsRequest = ({
  String path,
  Map<String, String> headers,
  Map<String, dynamic> body,
});

class FakeApns {
  FakeApns._(this._server);

  static Future<FakeApns> start() async {
    final server = await io.ServerSocket.bind(
      io.InternetAddress.loopbackIPv4,
      0,
    );
    final fake = FakeApns._(server);
    unawaited(fake._serve());
    return fake;
  }

  final io.ServerSocket _server;

  int get port => _server.port;

  /// Decides the reply for one device token. Defaults to accepting.
  ApnsReply Function(String deviceToken) replyFor = (_) => apnsOk;

  /// Every request that arrived, in arrival order.
  final requests = <ApnsRequest>[];

  /// The device token from each request's `:path`, in arrival order.
  List<String> get sentTokens => [
    for (final request in requests) request.path.split('/').last,
  ];

  /// The `authorization` header of each request, in arrival order. The
  /// provider token lives here, and the whole batch should share one.
  List<String> get authorizations => [
    for (final request in requests) request.headers['authorization'] ?? '',
  ];

  Future<void> _serve() async {
    await for (final socket in _server) {
      final connection = ServerTransportConnection.viaSocket(socket);
      unawaited(_handle(connection));
    }
  }

  Future<void> _handle(ServerTransportConnection connection) async {
    try {
      await for (final stream in connection.incomingStreams) {
        unawaited(_respond(stream));
      }
    } catch (_) {
      // A client closing mid-stream is normal here; the tests assert on what
      // arrived, never on how the connection ended.
    }
  }

  Future<void> _respond(ServerTransportStream stream) async {
    final received = <String, String>{};
    final body = StringBuffer();

    await for (final message in stream.incomingMessages) {
      switch (message) {
        case HeadersStreamMessage(headers: final incoming):
          for (final header in incoming) {
            received[ascii.decode(header.name)] = ascii.decode(header.value);
          }
        case DataStreamMessage(:final bytes):
          body.write(utf8.decode(bytes, allowMalformed: true));
      }
    }

    final path = received[':path'] ?? '';
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode('$body') as Map<String, dynamic>;
    } on FormatException {
      decoded = const {};
    }
    requests.add((path: path, headers: received, body: decoded));

    final reply = replyFor(path.split('/').last);

    stream.sendHeaders([
      Header.ascii(':status', '${reply.status}'),
      Header.ascii('apns-id', 'fake-apns-id'),
    ]);
    if (reply.reason case final reason?) {
      stream.sendData(
        utf8.encode(jsonEncode({'reason': reason})),
        endStream: true,
      );
    } else {
      await stream.outgoingMessages.close();
    }
  }

  Future<void> stop() => _server.close();
}
