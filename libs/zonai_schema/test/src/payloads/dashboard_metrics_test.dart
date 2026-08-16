import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/src/payloads/dashboard_metrics.dart';

/// The dashboard payload's wire shape.
///
/// This travels over IPC and then over HTTP, so a field that serializes but does
/// not deserialize fails only in the browser — which is the one place these
/// numbers are read. Every case below round-trips through real JSON text rather
/// than through the map, so a value that survives `toJson` but not `jsonEncode`
/// is caught here rather than in a panel showing a dash.
void main() {
  DashboardMetrics roundTrip(DashboardMetrics metrics) =>
      DashboardMetrics.fromJson(
        jsonDecode(jsonEncode(metrics.toJson())) as Map<String, dynamic>,
      );

  DashboardMetrics metricsWith({
    DashboardPushQueue? pushQueue,
    DashboardSessions? sessions,
  }) => DashboardMetrics(
    requestCount24h: 10,
    errorCount24h: 1,
    activeSessions: sessions?.active ?? 0,
    requestBuckets: const [DashboardRequestBucket(hour: 0, count: 3)],
    pushQueue:
        pushQueue ??
        const DashboardPushQueue(
          pending: 0,
          running: 0,
          completed: 0,
          failed: 0,
          delivered: 0,
          permanentlyRejected: 0,
          transientlyFailed: 0,
          failedJobs: [],
        ),
    sessions:
        sessions ??
        const DashboardSessions(
          active: 0,
          expiringWithinHour: 0,
          distinctUsers: 0,
          topUsers: [],
        ),
  );

  test('a fully populated payload survives a JSON round trip', () {
    final started = DateTime.fromMillisecondsSinceEpoch(1755300000000);
    final metrics = metricsWith(
      pushQueue: DashboardPushQueue(
        pending: 2,
        running: 1,
        completed: 7,
        failed: 3,
        delivered: 41000,
        permanentlyRejected: 12,
        transientlyFailed: 4,
        failedJobs: [
          DashboardPushFailure(
            id: 'pj_1',
            error: 'FCM 401',
            delivered: 40000,
            createdAt: started,
            updatedAt: started.add(const Duration(minutes: 3)),
          ),
        ],
        lastDrain: DashboardDrainRun(
          startedAt: started,
          failedAt: started.add(const Duration(seconds: 2)),
          error: 'APNs unreachable',
        ),
      ),
      sessions: const DashboardSessions(
        active: 9,
        expiringWithinHour: 2,
        distinctUsers: 4,
        topUsers: [DashboardSessionUser(userId: 'alice', sessionCount: 3)],
      ),
    );

    final decoded = roundTrip(metrics);

    expect(decoded.pushQueue.pending, 2);
    expect(decoded.pushQueue.delivered, 41000);
    expect(decoded.pushQueue.outstanding, 3);
    expect(decoded.pushQueue.failedJobs.single.id, 'pj_1');
    expect(decoded.pushQueue.failedJobs.single.error, 'FCM 401');
    expect(
      decoded.pushQueue.failedJobs.single.delivered,
      40000,
      reason:
          'the count that decides whether a failed job is safe to re-send has '
          'to survive the wire, not just the query',
    );
    expect(
      decoded.pushQueue.failedJobs.single.updatedAt,
      started.add(const Duration(minutes: 3)),
    );
    expect(decoded.pushQueue.lastDrain!.error, 'APNs unreachable');
    expect(decoded.pushQueue.lastDrain!.succeeded, isFalse);
    expect(decoded.sessions.active, 9);
    expect(decoded.sessions.expiringWithinHour, 2);
    expect(decoded.sessions.distinctUsers, 4);
    expect(decoded.sessions.topUsers.single.sessionCount, 3);
  });

  test('a never-drained queue decodes as null rather than as an epoch run', () {
    final decoded = roundTrip(metricsWith());

    expect(
      decoded.pushQueue.lastDrain,
      isNull,
      reason:
          'a synthetic run at the epoch would render as "drained in 1970" and '
          'read as a drain that happened',
    );
    expect(decoded.pushQueue.failedJobs, isEmpty);
    expect(decoded.sessions.topUsers, isEmpty);
  });

  test(
    'a failed job with no recorded reason keeps null, not an empty string',
    () {
      final at = DateTime.fromMillisecondsSinceEpoch(1755300000000);
      final decoded = roundTrip(
        metricsWith(
          pushQueue: DashboardPushQueue(
            pending: 0,
            running: 0,
            completed: 0,
            failed: 1,
            delivered: 0,
            permanentlyRejected: 0,
            transientlyFailed: 0,
            failedJobs: [
              DashboardPushFailure(
                id: 'pj_2',
                delivered: 0,
                createdAt: at,
                updatedAt: at,
              ),
            ],
          ),
        ),
      );

      expect(
        decoded.pushQueue.failedJobs.single.error,
        isNull,
        reason:
            '"failed with no reason recorded" and "failed with an empty message" '
            'are different situations, and the UI says so',
      );
    },
  );

  test('an in-flight drain is neither succeeded nor failed', () {
    final run = DashboardDrainRun(
      startedAt: DateTime.fromMillisecondsSinceEpoch(1755300000000),
    );

    expect(run.inProgress, isTrue);
    expect(run.succeeded, isFalse);
    expect(
      DashboardDrainRun.fromJson(
        jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>,
      ).inProgress,
      isTrue,
      reason: 'the drain fires every minute, so mid-run is a normal reading',
    );
  });

  test('active_sessions stays on the wire for the e2e driver', () {
    // `tool/ci/e2e/drive.dart` asserts this key by name. Renaming it silently
    // would turn that check into one that passes for the wrong reason.
    final json = metricsWith(
      sessions: const DashboardSessions(
        active: 5,
        expiringWithinHour: 0,
        distinctUsers: 5,
        topUsers: [],
      ),
    ).toJson();

    expect(json.containsKey('active_sessions'), isTrue);
    expect(json['active_sessions'], 5);
    expect(
      (json['sessions'] as Map)['active'],
      json['active_sessions'],
      reason: 'one query feeds both, so they cannot disagree',
    );
  });
}
