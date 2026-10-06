import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_client/server.dart';
import 'package:zonai_client/zonai_client.dart';

/// `ZonaiClient.server(...)` sends the stored token, like the factory does.
///
/// It did not: only the factory registered the auth interceptor, so a client
/// built with `.server` stored a token from `auth.setToken` and never sent it,
/// and every call answered 403 (reported by a consumer using an API token).
/// The interceptor is not exported, so a `.server` caller could not add it
/// either. Driven over a real socket, so what is asserted is the header that
/// actually arrives.
void main() {
  late HttpServer httpServer;
  late List<String?> authorizations;

  setUp(() async {
    authorizations = [];
    httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    httpServer.listen((request) async {
      authorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      await request.drain<void>();
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"data": {"count": 0}}');
      await request.response.close();
    });
  });

  tearDown(() => httpServer.close(force: true));

  Uri baseUrl() => Uri.parse('http://127.0.0.1:${httpServer.port}');

  Future<void> anyCall(ZonaiClient client) async {
    try {
      await client.db.count(body: const CountBody(table: 'posts'));
    } catch (_) {
      // Only the request matters here, not how the reply parses.
    }
  }

  test('a client built with .server sends the stored token', () async {
    final client = ZonaiClient.server(
      server: Server(baseUrl: baseUrl(), storage: ZonaiStorage.memory()),
    );
    await client.auth.setToken('an-api-token');

    await anyCall(client);

    expect(authorizations, ['Bearer an-api-token']);
  });

  test('the factory still sends it, once', () async {
    final client = ZonaiClient(
      baseUrl: baseUrl(),
      storage: ZonaiStorage.memory(),
    );
    await client.auth.setToken('an-api-token');

    await anyCall(client);

    expect(authorizations, ['Bearer an-api-token']);
  });

  test('two clients on one Server register one interceptor', () async {
    final server = Server(baseUrl: baseUrl(), storage: ZonaiStorage.memory());
    ZonaiClient.server(server: server);
    ZonaiClient.server(server: server);

    expect(server.client.interceptors, hasLength(1));
  });
}
