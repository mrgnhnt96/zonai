// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_client/zonai_client.dart';

/// An update refused on its `expect` reaches the caller as a typed
/// [PreconditionFailedException] carrying the rows as they are now.
///
/// Driven against a real `HttpServer` for the reason
/// `password_reset_required_test.dart` gives: the translation happens on a
/// `ServerException` that `revali_client` raises from a genuine non-2xx
/// response. The body served is the envelope
/// `apps/server/routes/components/exception_catcher.dart` produces for
/// `PreconditionFailedException`.
void main() {
  late _StubServer server;
  late ZonaiClient client;

  setUp(() async {
    server = await _StubServer.start();
    client = ZonaiClient(baseUrl: server.baseUrl, storage: ZonaiStorage.memory());
  });

  tearDown(() => server.close());

  const current = {'id': 'n1', 'title': 'v2', 'rev': 4};

  final preconditionFailed = _Reply(
    412,
    jsonEncode({
      'error': {
        'code': 'precondition_failed',
        'message': 'The update was refused: a target row does not meet expect',
        'details': {
          'current': [current],
        },
      },
    }),
  );

  Future<Object?> capture(Future<Object?> Function() request) async {
    try {
      await request();
    } catch (e) {
      return e;
    }
    fail('expected the update to throw');
  }

  test('update throws PreconditionFailedException with the current rows', () async {
    server.replies['/db'] = preconditionFailed;

    final refusal = await capture(
      () => client.db.update(
        body: const UpdateOneBody(
          table: 'notes',
          where: Eq('id', 'n1'),
          updates: [],
          expect: Eq('rev', 3),
        ),
        fromJson: (json) => json,
      ),
    );

    expect(refusal, isA<PreconditionFailedException>());
    expect((refusal! as PreconditionFailedException).current, [current]);
  });

  test('updateMany throws it too', () async {
    server.replies['/db/many'] = preconditionFailed;

    final refusal = await capture(
      () => client.db.updateMany(
        body: const UpdateBody(
          table: 'notes',
          where: Eq('owner_id', 'u1'),
          updates: [],
          expect: Eq('rev', 3),
        ),
        fromJson: (json) => json,
      ),
    );

    expect(refusal, isA<PreconditionFailedException>());
  });

  test('expect is sent on the wire', () async {
    server.replies['/db'] = const _Reply(200, '{"data": {"id": "n1"}}');

    await client.db.update(
      body: const UpdateOneBody(
        table: 'notes',
        where: Eq('id', 'n1'),
        updates: [],
        expect: Eq('rev', 3),
      ),
      fromJson: (json) => json,
    );

    final sent = jsonDecode(server.bodies['/db']!) as Map<String, Object?>;
    expect(sent['expect'], const Eq('rev', 3).toJson());
  });

  test('control: a 404 stays a ServerException', () async {
    server.replies['/db'] = const _Reply(404, '{"error": "Record not found (table: notes)"}');

    final refusal = await capture(
      () => client.db.update(
        body: const UpdateOneBody(table: 'notes', where: Eq('id', 'gone'), updates: []),
        fromJson: (json) => json,
      ),
    );

    expect(refusal, isA<ServerException>());
    expect((refusal! as ServerException).statusCode, 404);
  });

  test('control: a 412 with another code stays a ServerException', () async {
    server.replies['/db'] = _Reply(
      412,
      jsonEncode({
        'error': {'code': 'something_else', 'message': 'no'},
      }),
    );

    final refusal = await capture(
      () => client.db.update(
        body: const UpdateOneBody(table: 'notes', where: Eq('id', 'n1'), updates: []),
        fromJson: (json) => json,
      ),
    );

    expect(refusal, isA<ServerException>());
  });
}

final class _Reply {
  const _Reply(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _StubServer {
  _StubServer(this._server);

  static Future<_StubServer> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _StubServer(httpServer);
    httpServer.listen(server._handle);
    return server;
  }

  final HttpServer _server;

  final replies = <String, _Reply>{};
  final bodies = <String, String>{};

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    bodies[path] = await utf8.decoder.bind(request).join();

    final reply = replies[path] ?? const _Reply(404, '{"error":"no stub for this path"}');
    request.response
      ..statusCode = reply.statusCode
      ..headers.contentType = ContentType.json
      ..write(reply.body);
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
