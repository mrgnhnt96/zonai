import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/internal/crons/drain_push_jobs_cron.dart';

/// `_drain_push_jobs` must survive a host that cannot answer it.
///
/// `push_cron_messages_test` proves the request and response survive a round
/// trip and that the cron is registered. Neither says what the cron *does*
/// with a reply, and the behaviour that matters is a `try`/`catch` leaving no
/// other trace: `zonai_schema` and the CLI release on separate cadences, so a
/// project can legitimately run a newer schema than the binary driving it.
/// That host answers this request with an error. Letting it propagate fails
/// the job **every minute, indefinitely**, over a feature the deployment
/// simply does not have yet.
///
/// Deleting that catch looks like removing dead defensive code, and nothing
/// else in the suite goes red. That is what this file is for.
///
/// The logging behaviours are covered too, in the `logging` group, but only
/// because those tests drive the cron the way production does. `_loggerProvider`
/// is bound by the scope around the **listen loop**, not by `runWithParent`,
/// so a cron invoked directly writes its logs nowhere. An earlier draft of
/// this file did exactly that and its "an empty queue logs nothing" assertion
/// passed **vacuously** — the captured list was empty in every case, so the
/// one behaviour whose correctness *is* absence could not have failed. The
/// group below feeds a real `RunCronJobRequest` in through `incoming`
/// instead, which puts the cron inside `onMessage` where the logger is live.
class _FakeMessageIo implements MessageIo {
  final _incoming = StreamController<Map<String, dynamic>>();
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  void reply(Map<String, dynamic> message) => _incoming.add(message);

  @override
  void dispose() => _incoming.close();
}

void main() {
  /// Runs the real cron body, answering its request with [respond], and
  /// returns every message it put on the wire.
  Future<List<Map<String, dynamic>>> drainWith(
    Map<String, dynamic> Function(String requestId) respond,
  ) async {
    final io = _FakeMessageIo();
    final handler = MessageHandler<CronRequest>(
      fromUnknownRequest: CronRequest.fromRequest,
      onMessage: (request) async => null,
      io: io,
    );
    unawaited(handler.listen());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await handler.runWithParent(StartCronsRequest(), () async {
      await handler.runWithParent(
        RunCronJobRequest(name: '_drain_push_jobs'),
        () async {
          // Started rather than awaited, so the request reaches the wire and
          // can be answered below. The real cron body, never a restatement of
          // it — a copy here would keep passing after the original changed.
          final running = DrainPushJobsCron().run();

          final request = await _awaitDrainRequest(io);
          io.reply(respond(request['id'] as String));

          // That this completes at all is the assertion in every test below.
          await running;
        },
      );
    });

    return io.sent;
  }

  Map<String, dynamic> okResponse(String id) => DrainPushJobsResponse(
    id: id,
    jobsAdvanced: 2,
    jobsCompleted: 1,
    sent: 1250,
    permanentlyRejected: 7,
    transientlyFailed: 3,
    skipped: null,
  ).toJson();

  test('the drain runs as the cron, so internal rules admit it', () async {
    final sent = await drainWith(okResponse);

    final drains = sent
        .where((m) => '${m['path']}'.endsWith('.drain_push_jobs'))
        .toList();

    expect(drains, hasLength(1), reason: 'exactly one drain per firing');
    expect(
      drains.single['jwt'],
      {'CRON': true},
      reason:
          'the fan-out reads and writes internal tables. Without the cron '
          'identity the drain would be refused by the same rules that stop a '
          'user deleting a job, and the queue would stall silently',
    );
  });

  test('a host that does not know the path does not fail the job', () async {
    // The forward-compatibility path, and the whole reason for the catch.
    await expectLater(
      drainWith(
        (id) => MessageErrorResponse(
          id: id,
          message:
              'Unhandled request DrainPushJobsRequest(request/.drain_push_jobs)',
        ).toJson(),
      ),
      completes,
      reason:
          'an older binary answering with an error must not propagate. This '
          'cron fires every minute, so a throw here is a failed job and a '
          'stack trace every minute for as long as the mismatch lasts',
    );
  });

  test('a skipped drain does not fail the job either', () async {
    await expectLater(
      drainWith(
        (id) => DrainPushJobsResponse(
          id: id,
          jobsAdvanced: 0,
          jobsCompleted: 0,
          sent: 0,
          permanentlyRejected: 0,
          transientlyFailed: 0,
          skipped: 'AppConfig.push is not configured',
        ).toJson(),
      ),
      completes,
      reason: 'a project with no push config is not a broken project',
    );
  });

  test('an empty queue does not fail the job', () async {
    await expectLater(
      drainWith(
        (id) => DrainPushJobsResponse(
          id: id,
          jobsAdvanced: 0,
          jobsCompleted: 0,
          sent: 0,
          permanentlyRejected: 0,
          transientlyFailed: 0,
          skipped: null,
        ).toJson(),
      ),
      completes,
    );
  });

  group('logging', () {
    /// Drives the cron the way production does — an inbound
    /// `RunCronJobRequest` dispatched through `onMessage` — so it runs inside
    /// the listen-loop scope where `_loggerProvider` is bound and each log
    /// line leaves as a `DebugResponse`.
    Future<List<({String level, String message})>> logsFrom(
      Map<String, dynamic> Function(String requestId) respond,
    ) async {
      final io = _FakeMessageIo();
      final handler = MessageHandler<CronRequest>(
        fromUnknownRequest: CronRequest.fromRequest,
        onMessage: (request) async {
          if (request is! RunCronJobRequest) return null;
          await DrainPushJobsCron().run();
          return CronJobRunResponse(
            id: request.id,
            name: request.name,
            accepted: true,
          );
        },
        io: io,
      );
      unawaited(handler.listen());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      io.reply(RunCronJobRequest(name: '_drain_push_jobs').toJson());

      final drain = await _awaitDrainRequest(io);
      io.reply(respond(drain['id'] as String));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      return [
        for (final message in io.sent)
          if (message['path'] == 'response/.debug')
            (
              level: '${message['level']}',
              message: '${(message['payload'] as Map)['message']}',
            ),
      ];
    }

    test('a drain that did something says what it did', () async {
      final logs = await logsFrom(okResponse);

      expect(logs, hasLength(1));
      expect(logs.single.level, 'info');
      // The counts are the whole value of the line: "advanced 2 jobs" alone
      // cannot answer the question anyone actually arrives with, which is
      // whether their notifications went out.
      expect(logs.single.message, contains('2 push job(s)'));
      expect(logs.single.message, contains('1 completed'));
      expect(logs.single.message, contains('1250 sent'));
      expect(logs.single.message, contains('7 permanently rejected'));
      expect(logs.single.message, contains('3 transiently failed'));
    });

    test('an empty queue logs nothing at all', () async {
      final logs = await logsFrom(
        (id) => DrainPushJobsResponse(
          id: id,
          jobsAdvanced: 0,
          jobsCompleted: 0,
          sent: 0,
          permanentlyRejected: 0,
          transientlyFailed: 0,
          skipped: null,
        ).toJson(),
      );

      expect(
        logs,
        isEmpty,
        reason:
            'this fires every minute. A line per firing is 1,440 a day saying '
            'nothing happened, and the cost is not disk — it is that the one '
            'firing which did something stops standing out. This assertion is '
            'only meaningful because the sibling test above proves a log DOES '
            'reach this list when there is one to write',
      );
    });

    test(
      'a skip names its reason rather than reporting a quiet zero',
      () async {
        final logs = await logsFrom(
          (id) => DrainPushJobsResponse(
            id: id,
            jobsAdvanced: 0,
            jobsCompleted: 0,
            sent: 0,
            permanentlyRejected: 0,
            transientlyFailed: 0,
            skipped: 'AppConfig.push is not configured',
          ).toJson(),
        );

        expect(logs, hasLength(1));
        expect(logs.single.level, 'warn');
        expect(
          logs.single.message,
          contains('AppConfig.push is not configured'),
        );
      },
    );

    test('an older host warns, and names the likely cause', () async {
      final logs = await logsFrom(
        (id) => MessageErrorResponse(
          id: id,
          message:
              'Unhandled request DrainPushJobsRequest(request/.drain_push_jobs)',
        ).toJson(),
      );

      expect(logs, hasLength(1));
      expect(logs.single.level, 'warn');
      expect(logs.single.message, contains('Could not drain push jobs'));
      expect(
        logs.single.message,
        contains('predate push support'),
        reason:
            'the message has to name the likely cause. "Could not drain" '
            'alone sends someone to look at the queue rather than at the '
            'deployed binary version, which is where the answer is',
      );
    });
  });
}

/// The drain request the cron wrote, waited for rather than assumed.
Future<Map<String, dynamic>> _awaitDrainRequest(_FakeMessageIo io) async {
  for (var i = 0; i < 100; i++) {
    for (final message in io.sent) {
      if ('${message['path']}'.endsWith('.drain_push_jobs')) return message;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('the cron never wrote a drain_push_jobs request');
}
