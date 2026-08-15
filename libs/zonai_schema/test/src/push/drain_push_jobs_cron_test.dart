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
/// **What this does NOT cover, deliberately.** The cron's three logging
/// behaviours — silence on an empty queue, an info line carrying the counts
/// when work happened, and a warning naming a `skipped` reason — are not
/// asserted here. `MessageHandler.runWithParent` does not rebind
/// `_loggerProvider`; that happens only on the real inbound-request path, so
/// a log written in this harness goes nowhere and any assertion about log
/// *content* would pass whether or not the line was produced. An earlier
/// draft of this file asserted "an empty queue logs nothing" and passed
/// vacuously for exactly that reason. Covering it honestly needs the cron
/// driven through `db_crons` dispatch; until then the silence-on-empty-queue
/// guard — the one whose correct behaviour is *absence*, and so the easiest
/// to delete as a tidy-up — is genuinely unprotected.
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
