import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/internal/crons/cleanup_push_jobs_cron.dart';
import 'package:zonai_schema/src/types/where.dart';

/// What `_cleanup_push_jobs` is allowed to delete.
///
/// The registration test in `push_cron_messages_test.dart` proves the cron
/// exists and that `_push_jobs` is purgeable. Neither says anything about the
/// predicate, and the predicate is where the damage lives: **a running job's
/// row *is* its cursor.** Purge one by age and the next drain finds no
/// checkpoint, starts the fan-out from the top, and re-notifies every
/// recipient it had already reached — retention causing precisely the
/// duplicate the checkpoint exists to prevent, on real phones.
///
/// That is a one-word edit away at all times (`In` -> dropped, or a
/// `'running'` added while debugging a stuck job), it is invisible in review,
/// and nothing else in the suite would go red. Hence this file.
///
/// Asserted against the mutation as it reaches the wire rather than against a
/// database: `purge` is defined by the predicate it sends, so the wire form is
/// the whole behaviour, and a fixture database would only be able to show that
/// *these particular* rows survived.
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
  /// Runs the real cron and returns the purge it queued.
  Future<Map<String, dynamic>> runCron() async {
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
        RunCronJobRequest(name: '_cleanup_push_jobs'),
        () async {
          // Started rather than awaited. `mutate.purge` awaits a host
          // response, and this harness is deliberately only a wire: waiting
          // for a reply nobody sends hangs the test for the full 30s timeout.
          // What is under test is the predicate that goes *out*, which is on
          // the wire the moment the call is made.
          //
          // The real cron body, not a re-implementation of it — a copy of the
          // predicate here would keep passing after the original changed.
          unawaited(CleanupPushJobsCron().run());
          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
      );
    });

    final purges = io.sent
        .where((m) => '${m['path']}'.endsWith('.purge_records'))
        .toList();

    expect(
      purges,
      hasLength(1),
      reason: 'retention must reach the wire as exactly one purge',
    );
    return purges.single;
  }

  test('purges only finished jobs, never a running one', () async {
    final purge = await runCron();

    expect(purge['table'], '_push_jobs');

    final where = Where.fromJson(purge['where'] as Map<String, dynamic>);
    expect(where, isA<And>());

    final statuses = (where as And).conditions.whereType<In>().single;
    expect(statuses.column, 'status');
    expect(
      statuses.values,
      unorderedEquals(['completed', 'failed']),
      reason:
          'a running job\'s row is its cursor. Purging one restarts its '
          'fan-out from the top and re-notifies everyone it already reached, '
          'so `running` and `pending` must never appear here — and neither '
          'may the status filter be dropped for a plain age sweep',
    );
  });

  test('the cutoff is the retention window, not now', () async {
    final before = DateTime.now();
    final purge = await runCron();
    final after = DateTime.now();

    final where = Where.fromJson(purge['where'] as Map<String, dynamic>) as And;

    final age = where.conditions.whereType<Lt>().single;
    expect(age.column, 'updated_at');

    // Bracketed rather than compared to a fixed instant: the cron reads the
    // clock itself, so the only honest assertion is that the cutoff sits one
    // retention window behind the moment it ran.
    // Epoch milliseconds on the wire, not an ISO string — the comparison
    // below is between absolute instants either way, so local/UTC does not
    // enter into it.
    final cutoff = switch (age.value) {
      final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
      final value => DateTime.parse('$value'),
    };
    expect(
      cutoff.isAfter(before.subtract(CleanupPushJobsCron.retention)) ||
          cutoff.isAtSameMomentAs(
            before.subtract(CleanupPushJobsCron.retention),
          ),
      isTrue,
      reason: 'a cutoff older than the window would keep rows forever',
    );
    expect(
      cutoff.isBefore(after.subtract(CleanupPushJobsCron.retention)) ||
          cutoff.isAtSameMomentAs(
            after.subtract(CleanupPushJobsCron.retention),
          ),
      isTrue,
      reason:
          'a cutoff of "now" would delete jobs the moment they finished, '
          'which is the opposite of retention',
    );
  });

  test('retention outlives the complaint that prompts a look', () {
    // Not arbitrary: `_cleanup_logs` keeps four days, and this deliberately
    // keeps more. The reason to read a push job row is someone saying a
    // notification did or did not arrive, and that reaches a developer days
    // later rather than hours.
    expect(CleanupPushJobsCron.retention, const Duration(days: 7));
    expect(
      CleanupPushJobsCron.retention,
      greaterThan(const Duration(days: 4)),
      reason: 'shorter than the log window would defeat the point of the row',
    );
  });
}
