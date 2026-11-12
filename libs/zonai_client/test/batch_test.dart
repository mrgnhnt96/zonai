// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_client/zonai_client.dart';

/// `Db.batch` sends its steps to `POST /db/batch` and reads back one
/// [BatchResult] per step. Driven against a real `HttpServer`, as
/// `precondition_failed_test.dart` is, so the request and the refusal both
/// pass through `revali_client` for real.
void main() {
  late _StubServer server;
  late ZonaiClient client;

  setUp(() async {
    server = await _StubServer.start();
    client = ZonaiClient(baseUrl: server.baseUrl, storage: ZonaiStorage.memory());
  });

  tearDown(() => server.close());

  const body = BatchBody(
    operations: [
      BatchOperation.create(CreateBody(table: 'members', object: {'id': 'm1'})),
      BatchOperation.update(
        UpdateOneBody(
          table: 'orgs',
          where: Eq('id', 'o1'),
          updates: [
            ObjectUpdate({'owner': 'u2'}),
          ],
          expect: Eq('owner', 'u1'),
        ),
      ),
      BatchOperation.deleteMany(DeleteBody(table: 'invites', where: Eq('org', 'o1'))),
    ],
  );

  test('sends every step and reads back one result per step', () async {
    server.replies['/db/batch'] = _Reply(
      200,
      jsonEncode({
        'data': [
          {
            'op': 'create',
            'table': 'members',
            'count': 1,
            'rows': [
              {'id': 'm1'},
            ],
          },
          {
            'op': 'update',
            'table': 'orgs',
            'count': 1,
            'rows': [
              {'id': 'o1', 'owner': 'u2'},
            ],
          },
          {'op': 'deleteMany', 'table': 'invites', 'count': 3, 'rows': <Object?>[]},
        ],
      }),
    );

    final results = await client.db.batch(body: body);

    final sent = jsonDecode(server.bodies['/db/batch']!) as Map<String, Object?>;
    expect(
      [for (final step in sent['operations']! as List) (step as Map)['op']],
      ['create', 'update', 'deleteMany'],
    );

    expect([for (final r in results) r.op], ['create', 'update', 'deleteMany']);
    expect(results[1].rows, [
      {'id': 'o1', 'owner': 'u2'},
    ]);
    expect(results[2].count, 3);
  });

  test('a step refused on its expect throws PreconditionFailedException', () async {
    server.replies['/db/batch'] = _Reply(
      412,
      jsonEncode({
        'error': {
          'code': 'precondition_failed',
          'message': 'The update was refused: a target row does not meet expect',
          'details': {'current': <Object?>[]},
        },
      }),
    );

    Object? refusal;
    try {
      await client.db.batch(body: body);
    } catch (e) {
      refusal = e;
    }

    expect(refusal, isA<PreconditionFailedException>());
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
