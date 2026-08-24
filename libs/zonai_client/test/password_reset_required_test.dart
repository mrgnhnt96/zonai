// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:revali_client/revali_client.dart' show ServerException;
import 'package:test/test.dart';
import 'package:zonai_client/zonai_client.dart';

/// Driven against a REAL `HttpServer` rather than a stubbed data source.
///
/// The claim under test is "the typed exception is thrown from a real 403", and
/// a fake `AuthDataSource` cannot make it: the translation happens on a
/// `ServerException` that `revali_client` raises from a genuine non-2xx
/// response, so stubbing the data source would test the stub's ability to
/// throw. This serves the exact envelope
/// `apps/server/routes/components/exception_catcher.dart` produces --
/// `HttpError.forbidden(...).toEnvelope()` -- over a socket.
void main() {
  late _StubServer server;
  late ZonaiClient client;

  setUp(() async {
    server = await _StubServer.start();
    client = ZonaiClient(baseUrl: server.baseUrl, storage: ZonaiStorage.memory());
  });

  tearDown(() => server.close());

  group('a 403 password_reset_required', () {
    setUp(() {
      server.replies['/auth/sign-in'] = _forbiddenResetRequired;
      server.replies['/auth'] = _forbiddenResetRequired;
    });

    test('reaches signIn as a typed PasswordResetRequiredException', () async {
      final refusal = await _capture(
        () => client.auth.signIn(
          body: const SignInAuthBody(table: 'users', email: 'a@example.com', password: 'pw'),
        ),
      );

      expect(refusal.resetToken, 'dGhlLXRpY2tldA==');
      expect(refusal.reason, 'temporaryPassword');
      expect(refusal.message, 'This account must set a new password before signing in');
    });

    test('reaches the ADMIN door too', () async {
      // The one client that cannot wait: an admin forced to reset who cannot
      // complete it in the dashboard has no dashboard. Admin sign-in goes
      // through `/auth`, not `/auth/sign-in`, so translating only the latter
      // would leave this door holding a raw envelope.
      final refusal = await _capture(
        () => client.auth.admin.signIn(
          body: const AdminSignInAuthBody(email: 'a@example.com', password: 'pw'),
        ),
      );

      expect(refusal.resetToken, 'dGhlLXRpY2tldA==');
    });

    test('reads expiresIn as SECONDS', () async {
      // The wire carries 900. A `Duration` built from that number without the
      // unit is 900 milliseconds -- a ticket the client would treat as already
      // dead. Read as minutes it would be 15 hours. Neither is recoverable by
      // a caller, so the unit is asserted rather than assumed.
      final refusal = await _capture(
        () => client.auth.signIn(
          body: const SignInAuthBody(table: 'users', email: 'a@example.com', password: 'pw'),
        ),
      );

      expect(refusal.expiresIn, const Duration(minutes: 15));
    });

    test('never carries the ticket in toString()', () async {
      // Client exceptions land in crash reporters, analytics breadcrumbs and
      // `print`. A live credential in any of those outlives the 15 minutes it
      // was good for, somewhere nobody is watching. Same invariant the
      // server-side exception holds.
      final refusal = await _capture(
        () => client.auth.signIn(
          body: const SignInAuthBody(table: 'users', email: 'a@example.com', password: 'pw'),
        ),
      );

      expect('$refusal', isNot(contains(refusal.resetToken)));
      expect('$refusal', contains('temporaryPassword'));
    });
  });

  group('what must NOT be reshaped into it', () {
    test('an ordinary 401 stays a ServerException', () async {
      // The sign-in oracle contract: a wrong password and an unknown address
      // both answer 401 with a bare sentence. Turning that into a
      // PasswordResetRequiredException would send a caller off to collect a new
      // password for an account that may not exist.
      server.replies['/auth/sign-in'] = _Reply(
        401,
        jsonEncode({'error': 'Invalid password or email'}),
      );

      await expectLater(
        client.auth.signIn(
          body: const SignInAuthBody(table: 'users', email: 'a@example.com', password: 'pw'),
        ),
        throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('a 403 with a DIFFERENT code stays a ServerException', () async {
      server.replies['/auth/sign-in'] = _Reply(
        403,
        jsonEncode({
          'error': {'code': 'email_forbidden', 'message': 'no'},
        }),
      );

      await expectLater(
        client.auth.signIn(
          body: const SignInAuthBody(table: 'users', email: 'a@example.com', password: 'pw'),
        ),
        throwsA(isA<ServerException>().having((e) => e.code, 'code', 'email_forbidden')),
      );
    });

    test('a 403 carrying the right code but NO resetToken stays a ServerException', () async {
      // There is nothing to recover with. Handing a caller a typed exception
      // whose `resetToken` is empty would send it to `/auth/confirm` with a
      // credential that cannot work, and the failure would surface one call
      // further from its cause.
      server.replies['/auth/sign-in'] = _Reply(
        403,
        jsonEncode({
          'error': {
            'code': 'password_reset_required',
            'message': 'no',
            'details': <String, Object?>{},
          },
        }),
      );

      await expectLater(
        client.auth.signIn(
          body: const SignInAuthBody(table: 'users', email: 'a@example.com', password: 'pw'),
        ),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('completePasswordReset', () {
    test('confirms with the ticket, then signs in with the new password', () async {
      server.replies['/auth/sign-in'] = _forbiddenResetRequired;
      server.replies['/auth'] = _forbiddenResetRequired;

      final refusal = await _capture(
        () => client.auth.signIn(
          body: const SignInAuthBody(table: 'users', email: 'a@example.com', password: 'old-pw'),
        ),
      );

      // The confirm returns NO session -- that is the server's contract, and it
      // is the whole reason this helper exists rather than a one-call flow.
      server.replies['/auth/confirm'] = _Reply(200, jsonEncode({'data': null}));
      server.replies['/auth/sign-in'] = _Reply(
        200,
        jsonEncode({
          'data': {
            'accessToken': 'a.b.c',
            'user': <String, Object?>{'id': '1'},
          },
        }),
      );

      final session = await client.auth.completePasswordReset(
        refusal: refusal,
        email: 'a@example.com',
        newPassword: 'new-pw',
      );

      expect(session?.accessToken, 'a.b.c');

      final confirmBody = jsonDecode(server.bodies['/auth/confirm']!) as Map<String, Object?>;
      expect(confirmBody['type'], 'confirmResetPassword');
      expect(confirmBody['token'], refusal.resetToken);
      expect(confirmBody['newPassword'], 'new-pw');

      final signInBody = jsonDecode(server.bodies['/auth/sign-in']!) as Map<String, Object?>;
      expect(
        signInBody['password'],
        'new-pw',
        reason: 'the second call must use the password just chosen, not the one that was refused',
      );

      // And the session really landed in storage, which is what makes the
      // caller signed in rather than merely told it succeeded.
      expect(await client.auth.token, 'a.b.c');
    });

    test('propagates a 422 unchanged, so the caller can retry with the SAME ticket', () async {
      server.replies['/auth/sign-in'] = _forbiddenResetRequired;
      final refusal = await _capture(
        () => client.auth.signIn(
          body: const SignInAuthBody(table: 'users', email: 'a@example.com', password: 'old-pw'),
        ),
      );

      // The server does not consume the challenge on a reuse rejection --
      // `reset_password.dart` is explicit that the ordering is load-bearing,
      // because on the forced path there is no email to re-request. So this
      // must NOT be swallowed or reshaped: the caller still holds a good
      // ticket and needs to know only that the password was wrong.
      server.replies['/auth/confirm'] = _Reply(
        422,
        jsonEncode({'error': 'New password cannot be the same as the old password'}),
      );

      await expectLater(
        client.auth.completePasswordReset(
          refusal: refusal,
          email: 'a@example.com',
          newPassword: 'old-pw',
        ),
        throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 422)),
      );

      expect(await client.auth.token, isNull, reason: 'and nothing was signed in');
    });
  });
}

/// The exact envelope `Exceptions.onAuthException` builds through
/// `HttpError.forbidden(...).toEnvelope()`.
final _forbiddenResetRequired = _Reply(
  403,
  jsonEncode({
    'error': {
      'code': 'password_reset_required',
      'message': 'This account must set a new password before signing in',
      'details': {
        'resetToken': 'dGhlLXRpY2tldA==',
        'expiresIn': 900,
        'reason': 'temporaryPassword',
      },
    },
  }),
);

Future<PasswordResetRequiredException> _capture(Future<Object?> Function() action) async {
  try {
    final result = await action();
    fail('expected a PasswordResetRequiredException, got $result');
  } on PasswordResetRequiredException catch (e) {
    return e;
  }
}

class _Reply {
  const _Reply(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// A real socket answering scripted replies per path.
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

  /// The request body each path last received, so a test can assert what was
  /// SENT rather than only what came back.
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
