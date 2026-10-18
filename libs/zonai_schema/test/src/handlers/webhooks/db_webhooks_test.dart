import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/handlers/webhooks/db_webhooks.dart';
import 'package:zonai_schema/src/handlers/webhooks/webhook_message.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _FakeMessageIo implements MessageIo {
  final _incoming = StreamController<Map<String, dynamic>>();
  final List<Map<String, dynamic>> sent = [];
  final _sent = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) {
    sent.add(message);
    _sent.add(message);
  }

  /// Sends [message] the way the host would — through the real codec — and
  /// waits for the worker's answer to it.
  Future<Map<String, dynamic>> deliver(Map<String, dynamic> message) {
    final answer = _sent.stream.firstWhere(
      (m) => m['id'] == message['id'] && '${m['path']}'.startsWith('response/'),
    );
    final frame = IpcCodec.encode(message);
    _incoming.add(
      IpcCodec.decodePayload(Uint8List.sublistView(frame, IpcCodec.headerSize)),
    );
    return answer;
  }

  @override
  void dispose() {
    _incoming.close();
    _sent.close();
  }
}

final class _Hook extends Webhook {
  const _Hook(this.onHandle, {super.name = 'resend'});

  final Future<WebhookResponse> Function(WebhookRequest) onHandle;

  @override
  Future<WebhookResponse> handle(WebhookRequest request) => onHandle(request);
}

Future<_FakeMessageIo> _start(List<Webhook> webhooks) async {
  final io = _FakeMessageIo();
  DbWebhooks(webhooks: webhooks).start(io: io);
  await Future<void>.delayed(const Duration(milliseconds: 10));
  addTearDown(io.dispose);
  return io;
}

HandleWebhookRequest _delivery({String name = 'resend', String body = '{}'}) {
  return HandleWebhookRequest(
    name: name,
    body: Uint8List.fromList(utf8.encode(body)),
    headers: {'svix-id': 'msg_1', 'content-type': 'application/json'},
    ip: '203.0.113.9',
  );
}

void main() {
  group(DbWebhooks, () {
    test('hands the handler the body bytes, headers and ip as sent', () async {
      WebhookRequest? seen;
      final io = await _start([
        _Hook((request) async {
          seen = request;
          return const WebhookResponse.ok(body: 'thanks');
        }),
      ]);

      final request = _delivery(body: '{"type":"email.received"}');
      final answer = HandleWebhookResponse.fromJson(
        await io.deliver(request.toJson()),
      );

      expect(seen?.body, utf8.encode('{"type":"email.received"}'));
      expect(seen?.json, {'type': 'email.received'});
      expect(seen?.headers['svix-id'], 'msg_1');
      expect(seen?.ip, '203.0.113.9');
      expect(answer.found, isTrue);
      expect(answer.status, 200);
      expect(answer.body, 'thanks');
    });

    test('writes from the handler run as the server and belong to the '
        'delivery, so they commit when it answers', () async {
      final io = await _start([
        _Hook((request) async {
          mutate.create.one(tableName: 'inbound_emails', object: {'a': 1});
          return const WebhookResponse.ok();
        }),
      ]);

      final request = _delivery();
      await io.deliver(request.toJson());

      final create = io.sent.singleWhere(
        (m) => '${m['path']}'.endsWith('.create_record'),
      );
      expect(create['jwt'], CronJwt().toJson());
      expect((create['parent'] as Map)['id'], request.id);
    });

    test('an unknown name answers not found', () async {
      final io = await _start([_Hook((_) async => const WebhookResponse.ok())]);

      final answer = HandleWebhookResponse.fromJson(
        await io.deliver(_delivery(name: 'stripe').toJson()),
      );

      expect(answer.found, isFalse);
      expect(answer.status, 404);
    });

    test('a status the handler picks is passed back untouched', () async {
      final io = await _start([
        _Hook((_) async => const WebhookResponse(401, body: 'bad signature')),
      ]);

      final answer = HandleWebhookResponse.fromJson(
        await io.deliver(_delivery().toJson()),
      );

      expect(answer.status, 401);
      expect(answer.body, 'bad signature');
    });

    test('a handler that throws answers with an error', () async {
      final io = await _start([_Hook((_) async => throw StateError('boom'))]);

      final answer = await io.deliver(_delivery().toJson());

      expect(Response.fromJson(answer), isA<MessageErrorResponse>());
    });

    test('two webhooks with one name are refused', () {
      expect(
        () => DbWebhooks(
          webhooks: [
            _Hook((_) async => const WebhookResponse.ok()),
            _Hook((_) async => const WebhookResponse.ok()),
          ],
        ),
        throwsStateError,
      );
    });
  });
}
