import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';

class _FakeMessageIo implements MessageIo {
  final _incoming = StreamController<Map<String, dynamic>>();
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  @override
  void dispose() => _incoming.close();

  void push(Map<String, dynamic> message) => _incoming.add(message);
}

Future<void> _waitUntil(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  test(
    'a request that fails fromUnknownRequest replies with a '
    'MessageErrorResponse instead of crashing the listen loop -- one bad '
    'sender must not take down every other in-flight request',
    () async {
      final io = _FakeMessageIo();
      final handler = MessageHandler<RuleRequest>(
        fromUnknownRequest: RuleRequest.fromRequest,
        onMessage: (request) async {
          final request_ = request;
          if (request_ is RowRulesRequest) {
            return RowRulesResponse(
              id: request_.id,
              table: request_.table,
              operation: request_.operation,
              canPerform: true,
            );
          }
          return null;
        },
        io: io,
      );

      unawaited(handler.listen());

      // Stale sender: an update-operation row rules request with no
      // "updates" key -- throws StaleRowRulesRequestException inside
      // fromUnknownRequest, before onMessage ever runs.
      io.push({
        'path': 'request/.row.can_access',
        'id': 'req-1',
        'table': 'items',
        'operation': 'update',
        'data': {'id': 1},
      });

      // A perfectly normal request right behind it, on the same worker.
      io.push({
        'path': 'request/.row.can_access',
        'id': 'req-2',
        'table': 'items',
        'operation': 'view',
        'data': {'id': 2},
        'updates': <Object?>[],
      });

      await _waitUntil(() => io.sent.length >= 2);

      expect(io.sent[0]['path'], 'response/.error');
      expect(io.sent[0]['id'], 'req-1');

      expect(io.sent[1]['path'], 'response/.row.can_access');
      expect(io.sent[1]['id'], 'req-2');
      expect(io.sent[1]['payload']?['canPerform'], isTrue);

      io.dispose();
    },
  );
}
