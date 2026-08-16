import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    show Request, Response, UnknownRequest;
import 'package:zonai_schema/zonai_schema.dart';

/// Everything push puts on the wire, round-tripped through real JSON.
///
/// §12's last assertion, and the reason it is stated separately from the
/// engine tests: `push` crosses the worker/host boundary as encoded JSON, so
/// a field that serializes in-process and not over IPC passes every unit test
/// and fails in every real server. `jsonDecode(jsonEncode(...))` rather than
/// handing the map straight back is the point — it is what catches a value
/// that is not JSON-encodable at all.
Map<String, dynamic> _roundTrip(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  group('PushMessage', () {
    test('survives a JSON round trip', () {
      const original = PushMessage(
        title: 'Someone replied',
        body: 'Tap to read it',
        collapseKey: 'thread-42',
        data: {'lossEventId': 'evt_1', 'causedById': 'usr_2'},
      );

      final restored = PushMessage.fromJson(_roundTrip(original.toJson()));

      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.collapseKey, original.collapseKey);
      expect(restored.data, original.data);
      expect(restored, original);
    });

    test('an absent collapse key stays absent rather than becoming ""', () {
      const original = PushMessage(title: 'a', body: 'b');
      final json = _roundTrip(original.toJson());

      expect(json.containsKey('collapseKey'), isFalse);
      expect(PushMessage.fromJson(json).collapseKey, isNull);
    });

    test('an empty data map round trips as empty, not null', () {
      final restored = PushMessage.fromJson(
        _roundTrip(const PushMessage(title: 'a', body: 'b').toJson()),
      );
      expect(restored.data, isEmpty);
    });
  });

  group('PushMessage size', () {
    test('a realistic notification is nowhere near the limit', () {
      const typical = PushMessage(
        title: 'Morgan replied to your post',
        body: 'That is exactly the failure mode I was worried about.',
        collapseKey: 'post:evt_01HX9K2M',
        data: {'postId': 'evt_01HX9K2M', 'causedById': 'usr_01HX9K2N'},
      );

      expect(typical.tooLargeReason, isNull);
      expect(
        utf8.encode(jsonEncode(typical.toJson())).length,
        lessThan(500),
        reason:
            'the numbers are the argument against a template engine here: a '
            'real email template in apps/playground is ~6.8 KB, an order of '
            'magnitude more than an entire push payload',
      );
    });

    test('an over-limit message is refused, and says why', () {
      final huge = PushMessage(title: 'Digest', body: 'x' * 5000);

      expect(
        huge.tooLargeReason,
        allOf(contains('bytes'), contains('Shorten the body')),
        reason:
            'FCM answers an over-limit payload with INVALID_ARGUMENT, the '
            'same status a dead token gets — so an unchecked oversized '
            'message reaches the fan-out looking exactly like every '
            'recipient unregistering at once',
      );
    });

    test(
      'anything the budget accepts still fits FCM once the transport adds its parts',
      () {
        // The invariant the allowance exists for. Walk right up to the
        // boundary: the largest message that passes the check must still be
        // under the real limit after the transport wraps it with a
        // registration token and the platform blocks a collapse key expands
        // into. A budget that spent the whole 4096 would pass here and be
        // rejected by FCM as INVALID_ARGUMENT — which prunes tokens.
        for (final bodyLength in [1, 1000, 3000, 3500, 3560]) {
          final message = PushMessage(
            title: 'A notification title of a realistic length',
            body: 'x' * bodyLength,
            collapseKey: 'post:evt_01HX9K2M',
            data: const {'postId': 'evt_01HX9K2M'},
          );
          if (message.tooLargeReason != null) continue;

          final wire = utf8
              .encode(
                jsonEncode({
                  'message': {
                    'token':
                        'f' * 200, // longer than any token seen in practice
                    'notification': {
                      'title': message.title,
                      'body': message.body,
                    },
                    'data': message.data,
                    'android': {'collapse_key': message.collapseKey},
                    'apns': {
                      'headers': {'apns-collapse-id': message.collapseKey},
                    },
                  },
                }),
              )
              .length;

          expect(
            wire,
            lessThanOrEqualTo(PushMessage.maxPayloadBytes),
            reason:
                'a body of $bodyLength passed tooLargeReason but renders to '
                '$wire bytes on the wire, over the ${PushMessage.maxPayloadBytes}-byte '
                'limit — the overhead allowance is too small',
          );
        }
      },
    );
  });

  group('PushOutcome', () {
    test('each variant round trips as itself', () {
      final outcomes = <PushOutcome>[
        const PushDelivered(token: 'tok-a'),
        const PushPermanentlyRejected(
          token: 'tok-b',
          reason: PushRejectionReason.unregistered,
        ),
        const PushPermanentlyRejected(
          token: 'tok-c',
          reason: PushRejectionReason.invalidArgument,
        ),
        const PushTransientlyFailed(token: 'tok-d', detail: '503 UNAVAILABLE'),
      ];

      for (final outcome in outcomes) {
        final restored = PushOutcome.fromJson(_roundTrip(outcome.toJson()));
        expect(restored.runtimeType, outcome.runtimeType);
        expect(restored.token, outcome.token);

        switch ((outcome, restored)) {
          case (
            PushPermanentlyRejected(reason: final a),
            PushPermanentlyRejected(reason: final b),
          ):
            expect(b, a);
          case (
            PushTransientlyFailed(detail: final a),
            PushTransientlyFailed(detail: final b),
          ):
            expect(b, a);
          case _:
            break;
        }
      }
    });

    test('a permanent rejection is never decoded as a transient one', () {
      // The two are one field apart on the wire and worlds apart in effect:
      // one prunes a row, the other must never touch it.
      final rejected = PushOutcome.fromJson(
        _roundTrip(
          const PushPermanentlyRejected(
            token: 't',
            reason: PushRejectionReason.unregistered,
          ).toJson(),
        ),
      );

      expect(rejected, isA<PushPermanentlyRejected>());
      expect(rejected, isNot(isA<PushTransientlyFailed>()));
    });
  });

  group('PushConfig', () {
    test('survives a round trip, both credential forms', () {
      for (final credentials in <PushCredentials>[
        const PushCredentials.file('/keys/sa.json'),
        const PushCredentials.inline('{"type":"service_account"}'),
      ]) {
        final original = PushConfig(
          projectId: 'proj',
          credentials: credentials,
          onPermanentRejection: OnPermanentRejection.deleteRow,
          batchSize: 250,
          concurrency: 4,
          maxAttemptsPerBatch: 2,
        );

        final restored = PushConfig.fromJson(_roundTrip(original.toJson()));

        expect(restored.projectId, 'proj');
        expect(restored.onPermanentRejection, OnPermanentRejection.deleteRow);
        expect(restored.batchSize, 250);
        expect(restored.concurrency, 4);
        expect(restored.maxAttemptsPerBatch, 2);
        expect(restored.credentials.runtimeType, credentials.runtimeType);
      }
    });

    test('defaults to clearColumn when the wire omits the policy', () {
      final restored = PushConfig.fromJson({
        'projectId': 'proj',
        'credentials': const PushCredentials.inline('{}').toJson(),
      });

      // A destructive default has to be earned, and this one cannot be: an
      // app is free to put its token column on `users`, where `deleteRow`
      // would delete an account because a phone was wiped.
      expect(restored.onPermanentRejection, OnPermanentRejection.clearColumn);
    });
  });

  group('AppConfig', () {
    test('carries push through a round trip', () {
      final original = AppConfig(
        appName: 'app',
        passwordSecret: _passwordSecret,
        jwtSecret: _jwtSecret,
        push: const PushConfig(
          projectId: 'proj',
          credentials: PushCredentials.file('/keys/sa.json'),
        ),
      );

      final restored = AppConfig.fromJson(_roundTrip(original.toJson()));

      expect(restored.push, isNotNull);
      expect(restored.push!.projectId, 'proj');
      expect(restored.push!.credentials, isA<PushCredentialsFile>());
    });

    test('a project with no push config decodes as null, not a default', () {
      const original = AppConfig(
        appName: 'app',
        passwordSecret: _passwordSecret,
        jwtSecret: _jwtSecret,
      );

      final restored = AppConfig.fromJson(_roundTrip(original.toJson()));

      expect(
        restored.push,
        isNull,
        reason:
            'a fabricated default would turn "push is not configured" into '
            '"push is configured wrong", which fails much later and much '
            'less clearly',
      );
    });
  });

  group('EnqueuePushRequest', () {
    test('survives a round trip through Request.fromJson', () {
      final original = EnqueuePushRequest(
        message: const PushMessage(
          title: 'a',
          body: 'b',
          collapseKey: 'k',
          data: {'x': '1'},
        ),
        table: 'device_tokens',
        column: 'token',
        where: const In('user_id', ['u1', 'u2']),
        jwt: CronJwt(),
      );

      final restored = Request.fromJson(_roundTrip(original.toJson()));

      expect(restored, isA<EnqueuePushRequest>());
      restored as EnqueuePushRequest;
      expect(restored.id, original.id);
      expect(restored.table, 'device_tokens');
      expect(restored.column, 'token');
      expect(restored.message, original.message);
      expect(restored.where, isA<In>());
      expect((restored.where! as In).column, 'user_id');
      expect(
        restored.jwt?.admin.isAdmin,
        isTrue,
        reason:
            'the host gates the enqueue on an admin identity; an identity '
            'lost on the wire would turn every cron-issued push into a 403',
      );
    });

    test('a null where round trips as null, not an empty And', () {
      final original = EnqueuePushRequest(
        message: const PushMessage(title: 'a', body: 'b'),
        table: 't',
        column: 'c',
        where: null,
      );

      final restored =
          Request.fromJson(_roundTrip(original.toJson())) as EnqueuePushRequest;

      // An empty `And([])` renders as `WHERE ()`, which is a syntax error,
      // and "every row with a token" is a meaningful, different thing.
      expect(restored.where, isNull);
    });
  });

  group('EnqueuePushResponse', () {
    test('carries a job id, and carries null distinguishably', () {
      final withId = Response.fromJson(
        _roundTrip(EnqueuePushResponse(id: 'r1', jobId: 'abc_pj').toJson()),
      );
      expect(withId, isA<EnqueuePushResponse>());
      expect((withId as EnqueuePushResponse).jobId, 'abc_pj');

      final withoutId = Response.fromJson(
        _roundTrip(EnqueuePushResponse(id: 'r2', jobId: null).toJson()),
      );
      expect(
        (withoutId as EnqueuePushResponse).jobId,
        isNull,
        reason:
            'null is how the host reports "no AppConfig.push" — the worker '
            'turns it into a StateError where the stack still points at the '
            'code that asked to send',
      );
    });
  });

  group('PushRejectedExtensionRequest', () {
    test('survives a round trip through ExtensionRequest.fromRequest', () {
      final original = PushRejectedExtensionRequest(
        table: 'device_tokens',
        object: {'id': 'd1', 'token': 'tok-1', 'label': 'phone'},
        token: 'tok-1',
        reason: PushRejectionReason.unregistered,
        jwt: CronJwt(),
      );

      final json = _roundTrip(original.toJson());
      final restored = ExtensionRequest.fromRequest(
        UnknownRequest(
          path: json['path'] as String,
          id: json['id'] as String,
          payload: json,
          jwt: Jwt.maybeFromJson(json['jwt']),
        ),
      );

      expect(restored, isA<PushRejectedExtensionRequest>());
      restored as PushRejectedExtensionRequest;
      expect(restored.table, 'device_tokens');
      expect(restored.token, 'tok-1');
      expect(restored.reason, PushRejectionReason.unregistered);
      expect(
        restored.object['token'],
        'tok-1',
        reason:
            'the hook fires before the prune, so the row it receives must '
            'still carry the token that is about to be cleared',
      );
    });
  });

  group('PushJobId', () {
    test('round trips, and refuses a value that is not one', () {
      final id = PushJobId.generate();
      expect(PushJobId.fromJson(id.toJson()), id);
      expect(id.value, endsWith('pj'));

      expect(() => PushJobId('not-a-job-id'), throwsArgumentError);
    });
  });

  group('AppConfig.validate', () {
    AppConfig configWith(PushConfig push) => AppConfig(
      appName: 'app',
      passwordSecret: _passwordSecret,
      jwtSecret: _jwtSecret,
      push: push,
    );

    test('refuses a batch size that would send to nobody', () {
      // The worst shape a misconfiguration can take: `LIMIT 0` makes every
      // job read an empty batch, mark itself completed and send nothing --
      // no error, no log, and a jobs table full of rows that say they
      // finished. PushConfig's own bound is an `assert`, and asserts are
      // stripped from exactly the build where this would matter.
      expect(
        () => configWith(
          const PushConfig(
            projectId: 'p',
            credentials: PushCredentials.inline('{}'),
            batchSize: 0,
          ),
        ).validate(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('push.batchSize'),
          ),
        ),
      );
    });

    test('refuses a concurrency or attempt count below one', () {
      for (final push in [
        const PushConfig(
          projectId: 'p',
          credentials: PushCredentials.inline('{}'),
          concurrency: 0,
        ),
        const PushConfig(
          projectId: 'p',
          credentials: PushCredentials.inline('{}'),
          maxAttemptsPerBatch: 0,
        ),
        const PushConfig(
          projectId: '',
          credentials: PushCredentials.inline('{}'),
        ),
      ]) {
        expect(() => configWith(push).validate(), throwsStateError);
      }
    });

    test('a project with no push config still validates', () {
      expect(
        const AppConfig(
          appName: 'app',
          passwordSecret: _passwordSecret,
          jwtSecret: _jwtSecret,
        ).validate,
        returnsNormally,
      );
    });
  });

  group('deviceToken columns', () {
    test('are recognised as ColumnShapeKind.deviceToken', () {
      final shape = tableSchemaShapeFromTable(_tokens.$);
      final column = shape.columnNamed('token');

      expect(column, isNotNull);
      expect(
        column!.kind,
        ColumnShapeKind.deviceToken,
        reason:
            'this is the whole mechanism: push finds the token column '
            'through schemaShapes(), and refuses anything that is not one',
      );
      expect(
        shape.columnNamed('label')!.kind,
        isNot(ColumnShapeKind.deviceToken),
      );
    });

    test('the kind survives its own JSON round trip', () {
      final shape = tableSchemaShapeFromTable(_tokens.$);
      final restored = TableSchemaShape.fromJson(_roundTrip(shape.toJson()));

      expect(
        restored.columnNamed('token')!.kind,
        ColumnShapeKind.deviceToken,
        reason:
            'shapes reach the host as JSON from the operations worker; a '
            'kind that did not survive would make every push unresolvable',
      );
    });
  });
}

final class _TokenRow {
  const _TokenRow({required this.id, required this.token, required this.label});

  final String id;
  final String? token;
  final String label;
}

final class _TokensTable extends Table<_TokenRow> {
  _TokensTable(super.$)
    : id = $.text('id', (s) => s.id),
      token = $.deviceToken('token', (s) => s.token),
      label = $.text('label', (s) => s.label);

  @override
  _TokenRow fromRow(RowReader read) =>
      _TokenRow(id: read(id), token: read(token), label: read(label));

  final TextColumn id;
  final ColumnType<String?> token;
  final TextColumn label;
}

final _tokens = table('device_tokens', _TokensTable.new);

/// Real-shaped secrets: `AppConfig.validate()` rejects short and low-entropy
/// values, and these tests are about push, so a secret complaint here would be
/// noise reported as a push failure.
const _jwtSecret = 'push-wire-test-jwt-Qm3xR9vB2wLpZ4dHnT6yUsA8';
const _passwordSecret = 'push-wire-test-pw-Kf7YbQ5nTz9KwMr2VxHd4Cs';
