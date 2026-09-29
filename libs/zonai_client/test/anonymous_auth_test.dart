// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:revali_client/revali_client.dart' show ServerException, Storage;
import 'package:test/test.dart';
import 'package:zonai_client/zonai_client.dart';

/// The client half of anonymous accounts, against a REAL socket answering the
/// exact bodies `apps/server` produces -- including the `email_in_use`
/// envelope `exception_catcher.dart` builds with `HttpError.conflict`. A stub
/// data source could only test the stub's ability to throw.
void main() {
  late _StubServer server;
  late ZonaiClient client;
  late _RecordingStorage storage;

  setUp(() async {
    server = await _StubServer.start();
    storage = _RecordingStorage();
    client = ZonaiClient(baseUrl: server.baseUrl, storage: storage);
  });

  tearDown(() => server.close());

  group('signInAnonymously', () {
    test('returns the session and the credential, and stores only the session', () async {
      server.replies['/auth/anonymous'] = _Reply(200, jsonEncode(_anonymousSession));

      final created = await client.auth.signInAnonymously(table: 'users');

      expect(created.session.accessToken, _accessToken);
      expect(created.credential, 'zonai_anon_${'a' * 64}');
      expect(await client.auth.token, _accessToken);
      // The credential is the account. It goes to the app's secure storage,
      // never to the bearer-token storage an app may not have made secure.
      expect(storage.everSaved, isNotEmpty);
      expect(storage.everSaved.where((v) => '$v'.contains('zonai_anon_')), isEmpty);
      expect(jsonDecode(server.bodies['/auth/anonymous']!), {'table': 'users'});
    });
  });

  group('requestUpgrade and confirmUpgrade', () {
    setUp(() => client.auth.setToken(_accessToken));

    test('carry the stored anonymous session as the bearer', () async {
      server.replies['/auth/upgrade'] = const _Reply(200, '');

      await client.auth.requestUpgrade(email: 'ada@example.com');

      expect(server.authorization['/auth/upgrade'], 'Bearer $_accessToken');
      expect(jsonDecode(server.bodies['/auth/upgrade']!), {'email': 'ada@example.com'});
    });

    test('store the upgraded session', () async {
      server.replies['/auth/upgrade/confirm'] = _Reply(
        200,
        jsonEncode({
          'data': {
            'accessToken': 'upgraded.session.token',
            'user': {'id': 'u1', 'email': 'ada@example.com'},
          },
        }),
      );

      final session = await client.auth.confirmUpgrade(email: 'ada@example.com', code: '123456');

      expect(session.accessToken, 'upgraded.session.token');
      expect(await client.auth.token, 'upgraded.session.token');
    });

    test('a 409 email_in_use reaches the caller as EmailInUseException', () async {
      server.replies['/auth/upgrade/confirm'] = _conflict(code: 'email_in_use');

      await expectLater(
        client.auth.confirmUpgrade(email: 'taken@example.com', code: '123456'),
        throwsA(isA<EmailInUseException>()),
      );
      // Nothing changed: the anonymous session is still the stored one.
      expect(await client.auth.token, _accessToken);
    });

    test('a 409 with a DIFFERENT code stays a ServerException', () async {
      server.replies['/auth/upgrade/confirm'] = _conflict(code: 'something_else');

      await expectLater(
        client.auth.confirmUpgrade(email: 'ada@example.com', code: '123456'),
        throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 409)),
      );
    });
  });
}

const _accessToken = 'anonymous.session.token';

final _anonymousSession = {
  'data': {
    'accessToken': _accessToken,
    'user': {'id': 'u1', 'email': null},
    'anonymousCredential': 'zonai_anon_${'a' * 64}',
  },
};

/// The exact shape of `HttpError.conflict(...).toEnvelope()`.
_Reply _conflict({required String code}) => _Reply(
  409,
  jsonEncode({
    'error': {'code': code, 'message': 'That address already belongs to an account.'},
  }),
);

/// Records every value the client ever saves, not just what is left at the
/// end, so "the credential was never stored" is checked over the whole run.
final class _RecordingStorage implements Storage {
  final _data = <String, Object?>{};
  final everSaved = <Object?>[];

  @override
  Future<Object?> operator [](String key) async => _data[key];

  @override
  Future<void> save(String key, Object? value) async {
    everSaved.add(value);
    _data[key] = value;
  }

  @override
  Future<void> saveAll(Map<String, Object?> values) async {
    everSaved.addAll(values.values);
    _data.addAll(values);
  }

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> remove(String key) async => _data.remove(key);
}

class _Reply {
  const _Reply(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// A real socket answering scripted replies per path, recording what each
/// path was sent.
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
  final authorization = <String, String?>{};

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    bodies[path] = await utf8.decoder.bind(request).join();
    authorization[path] = request.headers.value(HttpHeaders.authorizationHeader);

    final reply = replies[path] ?? const _Reply(404, '{"error":"no stub for this path"}');
    request.response
      ..statusCode = reply.statusCode
      ..headers.contentType = ContentType.json
      ..write(reply.body);
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
