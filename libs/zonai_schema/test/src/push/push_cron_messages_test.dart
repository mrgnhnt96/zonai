import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import 'package:zonai_schema/src/internal/tables/push_jobs_table.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The `_drain_push_jobs` -> host round trip, and the registrations that make
/// the two push crons exist at all.
///
/// Every cron message crosses a process boundary and is reassembled by a
/// `switch` on its `path` string. Nothing type-checks that: a path matching no
/// case throws `Invalid cron request path` at runtime, on the job, in
/// production — and for the drain that means notifications silently stop
/// going out while the queue fills. Same reasoning as
/// `reclaim_log_space_message_test`.
void main() {
  group('DrainPushJobsRequest', () {
    test('survives a round trip through CronRequest.fromJson', () {
      final sent = DrainPushJobsRequest();
      final received = CronRequest.fromJson(sent.toJson());

      expect(received, isA<DrainPushJobsRequest>());
      expect(received.id, sent.id);
    });

    test('survives the fromRequest path the worker actually uses', () {
      // `CronRequest.fromJson` and `CronRequest.fromRequest` are two separate
      // switches over the same path strings, and only one of them is on the
      // worker's receive path. A case added to one and forgotten in the other
      // passes the test above and fails in the worker.
      final sent = DrainPushJobsRequest();
      final json = sent.toJson();

      final received = CronRequest.fromRequest(
        UnknownRequest(
          path: json['path'] as String,
          id: json['id'] as String,
          payload: json,
        ),
      );

      expect(received, isA<DrainPushJobsRequest>());
      expect(received.id, sent.id);
    });
  });

  group('DrainPushJobsResponse', () {
    test('survives a round trip, counts intact', () {
      final sent = DrainPushJobsResponse(
        id: 'abc',
        jobsAdvanced: 3,
        jobsCompleted: 1,
        sent: 1250,
        permanentlyRejected: 7,
        transientlyFailed: 2,
        skipped: null,
      );

      final received = CronResponse.fromJson(sent.toJson());

      expect(received, isA<DrainPushJobsResponse>());
      final result = received as DrainPushJobsResponse;
      expect(result.jobsAdvanced, 3);
      expect(result.jobsCompleted, 1);
      expect(result.sent, 1250);
      expect(result.permanentlyRejected, 7);
      expect(result.transientlyFailed, 2);
      expect(result.skipped, isNull);
    });

    test('carries a skip reason rather than reporting a quiet zero', () {
      final received =
          CronResponse.fromJson(
                DrainPushJobsResponse(
                  id: 'abc',
                  jobsAdvanced: 0,
                  jobsCompleted: 0,
                  sent: 0,
                  permanentlyRejected: 0,
                  transientlyFailed: 0,
                  skipped: 'AppConfig.push is not configured',
                ).toJson(),
              )
              as DrainPushJobsResponse;

      expect(
        received.skipped,
        'AppConfig.push is not configured',
        reason:
            'zeros with no reason are indistinguishable from a healthy empty '
            'queue, which is how "nothing is being delivered" goes unnoticed',
      );
    });
  });

  group('registration', () {
    test('both push crons are registered as internal artifacts', () {
      final aliases = [
        for (final cron in InternalDbArtifacts.crons) cron.alias,
      ];

      // A cron file that exists but is not in the generated artifacts list is
      // never compiled into `db_crons`, so it never runs — and nothing about
      // the source file would say so.
      expect(aliases, contains('zonai_internal_drain_push_jobs_cron'));
      expect(aliases, contains('zonai_internal_cleanup_push_jobs_cron'));
    });

    test('_push_jobs is a registered internal table', () {
      expect(InternalDbArtifacts.tableNames, contains('_push_jobs'));
      expect([
        for (final t in InternalDbArtifacts.tables) t.tableName,
      ], contains('_push_jobs'));
    });

    test('_push_jobs is purgeable, so retention can actually drain it', () {
      // `_purgeableTables` is derived as every internal table except
      // `_photos`. Retention uses `mutate.purge`, and purge refuses a table
      // outside that set — so a table that fell out of the derivation would
      // make the nightly cron fail rather than silently skip, but it would
      // still mean the table grows forever.
      expect(
        InternalDbArtifacts.tableNames.difference({'_photos'}),
        contains('_push_jobs'),
      );
    });
  });

  group('PushJobEntry', () {
    test('a created job starts pending, uncounted, and with no cursor', () {
      final entry = PushJobEntry.create(
        message: const PushMessage(title: 'a', body: 'b'),
        targetTable: 'device_tokens',
        targetColumn: 'token',
        where: const Eq('user_id', 'u1'),
      );

      expect(entry.status, PushJobStatus.pending);
      expect(
        entry.cursor,
        isNull,
        reason: 'a null cursor is what makes the first batch start at the top',
      );
      expect(entry.delivered, 0);
      expect(entry.permanentlyRejected, 0);
      expect(entry.transientlyFailed, 0);
      expect(entry.error, isNull);
      expect(entry.id.value, endsWith('pj'));
    });

    test('the stored message and where decode back to what was enqueued', () {
      const message = PushMessage(
        title: 'New reply',
        body: 'Someone replied',
        collapseKey: 'post:1',
        data: {'postId': '1'},
      );

      final entry = PushJobEntry.create(
        message: message,
        targetTable: 'device_tokens',
        targetColumn: 'token',
        where: const In('user_id', ['u1', 'u2']),
      );

      // The job stores the rendered message rather than referencing it, so a
      // resumed fan-out sends what was enqueued rather than what the code
      // says today. That only holds if it decodes back intact.
      expect(entry.pushMessage, message);
      expect(entry.where, isA<In>());
      expect((entry.where! as In).column, 'user_id');
    });

    test('a job with no where decodes as null, not an empty predicate', () {
      final entry = PushJobEntry.create(
        message: const PushMessage(title: 'a', body: 'b'),
        targetTable: 'device_tokens',
        targetColumn: 'token',
        where: null,
      );

      expect(entry.whereJson, isNull);
      expect(
        entry.where,
        isNull,
        reason:
            'an empty And([]) renders as `WHERE ()`, a syntax error — and '
            '"every row with a token" is a different, meaningful thing',
      );
    });
  });
}
