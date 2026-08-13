import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/types/where.dart';

// Reported from wholesale-command-station, 2026-08-13: `_delete_old_rate_limits`
// had run 1,256 times against a 42-row table with 39 rows past its cutoff and
// deleted nothing, while `_cleanup_logs` had run 13 times against 4.6M rows and
// also deleted nothing. Five orders of magnitude apart, both zero, no error
// recorded on any of the 1,269 runs.
//
// That span is what rules out every explanation involving volume. What is left
// is something that happens before the row count matters -- and the candidate
// is which `parent` the queued mutation is attached to, because that id is what
// the host keys `_pendingMutations` by and later flushes on the matching
// response.
class _FakeMessageIo implements MessageIo {
  final _incoming = StreamController<Map<String, dynamic>>();
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  @override
  void dispose() => _incoming.close();
}

void main() {
  test(
    'a mutation queued inside a nested runWithParent is attached to the OUTER '
    'request -- which is how a scheduled cron\'s delete is parked against a '
    'response the host already answered at startup',
    () async {
      final io = _FakeMessageIo();
      final handler = MessageHandler<CronRequest>(
        fromUnknownRequest: CronRequest.fromRequest,
        onMessage: (request) async => null,
        io: io,
      );
      unawaited(handler.listen());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // `StartCronsRequest` stands in for the real outer scope: `_startCrons`
      // runs inside `runWithParent(StartCronsRequest)`, and `cron.schedule`'s
      // timers capture that zone, so every later scheduled firing is still
      // inside it.
      final start = StartCronsRequest();

      // `RunCronJobRequest` is what `_runJob` fabricates per firing and passes
      // to its own `runWithParent`.
      final run = RunCronJobRequest(name: '_cleanup_logs');

      await handler.runWithParent(start, () async {
        await handler.runWithParent(run, () async {
          mutate.delete.many(
            tableName: '_log',
            where: Lt('timestamp', DateTime.utc(2020)),
          );
        });
      });

      final deletes = io.sent
          .where((m) => '${m['path']}'.endsWith('.delete_record'))
          .toList();

      expect(
        deletes,
        hasLength(1),
        reason: 'the delete must at least be written to the wire',
      );

      final parentId = (deletes.single['parent'] as Map)['id'];

      // Positive control first: naming which id it actually is, so a future
      // failure here reports a changed mechanism rather than just "not run.id".
      expect(
        parentId,
        start.id,
        reason:
            'BUG: the inner runWithParent uses `includeIfAbsent`, so with '
            '_mutateProvider already bound by the outer scope the inner '
            'binding is skipped and the mutation inherits the OUTER parent. '
            'The host keys _pendingMutations by that id and flushes it when '
            'the matching response arrives -- which for StartCronsRequest '
            'already happened at startup. Every later scheduled firing parks '
            'a mutation there that nothing will ever flush.',
      );

      expect(
        parentId,
        isNot(run.id),
        reason:
            'the mutation belongs to the cron firing that queued it; this is '
            'the assertion that should hold once the binding is fixed',
      );
    },
  );

  test(
    'a timer created inside runWithParent still carries that scope when it '
    'fires later -- which is what makes every scheduled firing nest inside '
    'StartCronsRequest rather than standing alone',
    () async {
      final io = _FakeMessageIo();
      final handler = MessageHandler<CronRequest>(
        fromUnknownRequest: CronRequest.fromRequest,
        onMessage: (request) async => null,
        io: io,
      );
      unawaited(handler.listen());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final start = StartCronsRequest();
      final fired = Completer<void>();

      // `_startCrons` calls `cron.schedule(...)` from inside this scope. The
      // `cron` package schedules with a Timer, and a Dart Timer runs its
      // callback in the zone it was created in -- so the scope below is still
      // active on every later firing, long after CronsStarted was answered.
      await handler.runWithParent(start, () async {
        Timer(const Duration(milliseconds: 5), () async {
          await handler.runWithParent(
            RunCronJobRequest(name: '_delete_old_rate_limits'),
            () async {
              mutate.delete.many(
                tableName: '_rate_limit',
                where: Lt('timestamp', DateTime.utc(2020)),
              );
            },
          );
          fired.complete();
        });
      });

      await fired.future;

      final deletes = io.sent
          .where((m) => '${m['path']}'.endsWith('.delete_record'))
          .toList();

      expect(deletes, hasLength(1));
      expect(
        (deletes.single['parent'] as Map)['id'],
        start.id,
        reason:
            'a firing that happens minutes or hours after startup still '
            'attaches its mutation to the startup request. This is why '
            '_delete_old_rate_limits deleted nothing across 1,256 runs '
            'against a 42-row table: the row count was never reached.',
      );
    },
  );
}
