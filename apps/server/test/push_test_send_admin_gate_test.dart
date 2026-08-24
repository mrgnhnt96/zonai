import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';
import 'package:zonai_schema/src/types/push_message.dart';
import 'package:zonai_server/src/handlers/push_handler.dart';

/// The test-send endpoint is admin-only, and refuses before it sends.
///
/// "Before it sends" is the property that matters, and it is not the same as
/// "returns an error". This endpoint reaches a real push transport and a real
/// device: a handler that sent the notification and *then* threw would pass a
/// test that only checked the exception, while having pushed to somebody's
/// phone on behalf of a caller who was never authorized. So the assertion is
/// on the engine having been left untouched.
void main() {
  Jwt jwtWith({required bool isAdmin}) => Jwt(
    userId: UnknownId('u'),
    table: '_user',
    jwtId: JwtId('j'),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const {},
    claims: const {},
    admin: (isAdmin: isAdmin, canEdit: isAdmin ? true : null),
  );

  const body = PushTestSendBody(
    table: 'users',
    column: 'deviceToken',
    token: 'a-device-token',
    title: 'Test notification',
    body: 'Sent from the Zonai dashboard.',
  );

  /// The three ways a caller can fail to be an admin.
  final rejectedCallers = <String, ({Jwt? jwt, String? authorization})>{
    'a signed-in caller who is not an admin': (
      jwt: jwtWith(isAdmin: false),
      authorization: 'Bearer some-token',
    ),
    'a caller with no Authorization header at all': (
      jwt: null,
      authorization: null,
    ),
    // `parseJwt` answers null for a token it cannot verify, which has to read
    // as "not an admin" rather than falling through.
    'a token that does not parse': (jwt: null, authorization: 'Bearer garbage'),
  };

  for (final MapEntry(key: who, value: caller) in rejectedCallers.entries) {
    test('refuses $who', () async {
      final db = _StubZonaiDb(jwt: caller.jwt);

      await runScoped(
        () async {
          await expectLater(
            const PushHandler().sendTest(caller.authorization, body: body),
            throwsA(isA<TableAccessDeniedException>()),
          );
          expect(
            db.acted,
            isEmpty,
            reason:
                'the refusal has to come before the send -- this endpoint '
                'reaches a real transport and a real device, so a handler that '
                'sent and then threw would have pushed to a phone for an '
                'unauthorized caller. Reached: ${db.acted}',
          );
        },
        values: {
          zonaiDbProvider.overrideWith(
            () =>
                () => db,
          ),
        },
      );
    });
  }

  test('lets an admin through to the engine', () async {
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    await runScoped(
      () async {
        await const PushHandler().sendTest('Bearer admin-token', body: body);
        expect(
          db.acted,
          isNotEmpty,
          reason:
              'a gate that refuses everyone would pass the tests above for the '
              'wrong reason',
        );
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
  });

  test('passes the target, token and platform through untouched', () async {
    final db = _StubZonaiDb(jwt: jwtWith(isAdmin: true));

    await runScoped(
      () async {
        await const PushHandler().sendTest(
          'Bearer admin-token',
          body: const PushTestSendBody(
            table: 'devices',
            column: 'apnsToken',
            // Whitespace around a pasted token is the normal result of copying
            // one out of a console, and would otherwise be sent verbatim and
            // rejected as malformed.
            token: '  padded-token \n',
            title: 'Hello',
            body: 'World',
            platform: DevicePlatform.ios,
          ),
        );

        expect(db.sentTable, 'devices');
        expect(db.sentColumn, 'apnsToken');
        expect(db.sentToken, 'padded-token');
        expect(db.sentPlatform, DevicePlatform.ios);
        expect(db.sentMessage?.title, 'Hello');
        expect(db.sentMessage?.body, 'World');
        // A fan-out sets a collapse key so a crash-resumed duplicate is
        // invisible on the device. A test send must not: an operator pressing
        // the button twice wants to see two notifications, not one replacing
        // the other and looking like the second never arrived.
        expect(db.sentMessage?.collapseKey, isNull);
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
  });

  test('reports the provider reason the engine returned, unchanged', () async {
    final db = _StubZonaiDb(
      jwt: jwtWith(isAdmin: true),
      result: const PushTestSendResult(
        status: PushTestSendStatus.rejected,
        token: 'a-device-token',
        transport: 'apns',
        reason: PushRejectionReason.unregistered,
        detail: '400 BadDeviceToken',
      ),
    );

    await runScoped(
      () async {
        final result = await const PushHandler().sendTest(
          'Bearer admin-token',
          body: body,
        );

        // The whole point of the endpoint. A handler that collapsed this to
        // "rejected" would send an operator to look at a device that is working
        // perfectly, when the answer is that the token belongs to the other
        // APNs environment.
        expect(result.status, PushTestSendStatus.rejected);
        expect(result.detail, '400 BadDeviceToken');
        expect(result.transport, 'apns');
      },
      values: {
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
  });
}

/// A [ZonaiDb] that answers a fixed [Jwt] and records what it was asked to send.
///
/// [acted] is the load-bearing field: the gate's job is to keep it empty for
/// an unauthorized caller.
class _StubZonaiDb implements ZonaiDb {
  _StubZonaiDb({required this.jwt, this.result});

  final Jwt? jwt;
  final PushTestSendResult? result;

  final List<String> acted = [];
  String? sentTable;
  String? sentColumn;
  String? sentToken;
  DevicePlatform? sentPlatform;
  PushMessage? sentMessage;

  @override
  // `allowApiToken` is accepted and ignored: this stub answers with whatever
  // identity the case under test set up, and these routes never opt in
  // anyway. Present because the real signature has it -- an override that
  // drops it does not compile, which is how this file stopped loading at all
  // when `parseJwt` grew the parameter.
  Future<Jwt?> parseJwt(String? token, {bool allowApiToken = false}) async =>
      jwt;

  @override
  Future<PushTestSendResult> sendTestPush({
    required PushMessage message,
    required String table,
    required String column,
    required String token,
    required DevicePlatform? platform,
    required Jwt? jwt,
  }) async {
    acted.add('sendTestPush');
    sentTable = table;
    sentColumn = column;
    sentToken = token;
    sentPlatform = platform;
    sentMessage = message;

    return result ??
        PushTestSendResult(
          status: PushTestSendStatus.accepted,
          token: token,
          transport: 'fcm',
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
