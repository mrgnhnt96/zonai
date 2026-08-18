class DashboardRequestBucket {
  const DashboardRequestBucket({required this.hour, required this.count});

  final int hour;
  final int count;

  factory DashboardRequestBucket.fromJson(Map<String, dynamic> json) {
    return DashboardRequestBucket(
      hour: json['hour'] as int,
      count: json['count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'hour': hour, 'count': count};
}

/// One push fan-out that stopped, and the reason it stopped.
///
/// [delivered] travels with the error on purpose. "Failed" alone does not say
/// whether anybody got the notification, and the two cases need opposite
/// responses: a job that failed having reached nobody can be re-sent, while one
/// that failed at recipient 40,000 of 50,000 cannot be re-sent without
/// notifying those 40,000 twice.
class DashboardPushFailure {
  const DashboardPushFailure({
    required this.id,
    required this.delivered,
    required this.createdAt,
    required this.updatedAt,
    this.error,
  });

  /// The `_push_jobs` row's id, so an operator can go and read the row.
  final String id;

  /// Why the job stopped. `null` for a row marked failed with no reason
  /// recorded — which is a different situation from an empty message, and is
  /// why this is nullable rather than defaulted to `''`.
  final String? error;

  /// Recipients this job reached before it stopped.
  final int delivered;

  final DateTime createdAt;
  final DateTime updatedAt;

  factory DashboardPushFailure.fromJson(Map<String, dynamic> json) {
    return DashboardPushFailure(
      id: json['id'] as String,
      error: json['error'] as String?,
      delivered: json['delivered'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'error': error,
    'delivered': delivered,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

/// The most recent `_drain_push_jobs` run, read from `_cron_jobs`.
///
/// **This deliberately carries no `sent` count, and that is not an oversight.**
/// `DrainPushJobsResponse.sent` — the one number that distinguishes a drain
/// doing its job from one spinning on an empty queue — is returned to the cron
/// and then only written to `_log` as prose. Nothing persists it as a column,
/// so the only honest thing this can report about the last drain is that it
/// ran, and whether it broke. Inventing a `sent` here by summing job counters
/// would report a lifetime total as if it were one pass's output.
///
/// Where delivery *is* answerable is [DashboardPushQueue.delivered], which is a
/// sum over retained job rows and is labelled as such.
class DashboardDrainRun {
  const DashboardDrainRun({
    required this.startedAt,
    this.completedAt,
    this.failedAt,
    this.error,
  });

  final DateTime startedAt;

  /// When the drain finished cleanly, or `null` if it has not.
  final DateTime? completedAt;

  /// When the drain failed, or `null` if it did not.
  final DateTime? failedAt;

  /// The failure's message, when [failedAt] is set.
  final String? error;

  /// Whether the last drain finished cleanly.
  ///
  /// A run that is neither completed nor failed is still in flight — the drain
  /// fires every minute, so catching one mid-run is ordinary, not a fault.
  bool get succeeded => completedAt != null && failedAt == null;

  /// Whether the last drain is still running.
  bool get inProgress => completedAt == null && failedAt == null;

  factory DashboardDrainRun.fromJson(Map<String, dynamic> json) {
    return DashboardDrainRun(
      startedAt: DateTime.fromMillisecondsSinceEpoch(json['started_at'] as int),
      completedAt: switch (json['completed_at']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
      failedAt: switch (json['failed_at']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'started_at': startedAt.millisecondsSinceEpoch,
    'completed_at': completedAt?.millisecondsSinceEpoch,
    'failed_at': failedAt?.millisecondsSinceEpoch,
    'error': error,
  };
}

/// The state of the `_push_jobs` queue.
///
/// Depth is reported per status rather than as one number because the statuses
/// mean opposite things: [pending] and [running] are work outstanding, while
/// [completed] and [failed] are history that `_cleanup_push_jobs` prunes after
/// seven days. A single "12 jobs" mixes a backlog with a scrollback.
class DashboardPushQueue {
  const DashboardPushQueue({
    required this.pending,
    required this.running,
    required this.completed,
    required this.failed,
    required this.delivered,
    required this.permanentlyRejected,
    required this.transientlyFailed,
    required this.failedJobs,
    this.lastDrain,
  });

  /// Enqueued, not yet claimed by a drain.
  final int pending;

  /// Claimed by a drain and part-way through its recipients. Not "a process is
  /// working on it right now" — nothing holds a lock, so a crashed drain leaves
  /// a row here with a cursor for the next one to resume from.
  final int running;

  final int completed;
  final int failed;

  /// Recipients reached, summed across the job rows still retained.
  ///
  /// **A lifetime figure for the retained window, not one drain's output.**
  /// `_cleanup_push_jobs` purges finished jobs after seven days, so this falls
  /// when retention runs and is a floor on everything ever sent, never a total.
  /// It is still the number that answers "has any notification actually gone
  /// out", which no count of jobs can.
  final int delivered;

  /// Recipients the transport rejected for good — a dead token, summed the same
  /// way as [delivered].
  final int permanentlyRejected;

  /// Recipients a pass could not reach but a later one may, summed the same way
  /// as [delivered].
  final int transientlyFailed;

  /// Jobs in [PushJobStatus.failed], most recently updated first.
  final List<DashboardPushFailure> failedJobs;

  /// The most recent `_drain_push_jobs` run, or `null` when it has never run in
  /// the window `_cleanup_cron_entries` retains.
  final DashboardDrainRun? lastDrain;

  /// Jobs still to be worked: enqueued plus part-way through.
  ///
  /// Deliberately excludes [completed] and [failed]: this is the number that
  /// should be zero on a healthy idle deployment, and folding history in would
  /// make it permanently non-zero for a week after every send.
  int get outstanding => pending + running;

  factory DashboardPushQueue.fromJson(Map<String, dynamic> json) {
    return DashboardPushQueue(
      pending: json['pending'] as int,
      running: json['running'] as int,
      completed: json['completed'] as int,
      failed: json['failed'] as int,
      delivered: json['delivered'] as int,
      permanentlyRejected: json['permanently_rejected'] as int,
      transientlyFailed: json['transiently_failed'] as int,
      failedJobs: [
        for (final job in json['failed_jobs'] as List)
          DashboardPushFailure.fromJson(Map<String, dynamic>.from(job as Map)),
      ],
      lastDrain: switch (json['last_drain']) {
        final Map<Object?, Object?> run => DashboardDrainRun.fromJson(
          Map<String, dynamic>.from(run),
        ),
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'pending': pending,
    'running': running,
    'completed': completed,
    'failed': failed,
    'delivered': delivered,
    'permanently_rejected': permanentlyRejected,
    'transiently_failed': transientlyFailed,
    'failed_jobs': [for (final job in failedJobs) job.toJson()],
    'last_drain': lastDrain?.toJson(),
  };
}

/// One user and how many live sessions they are holding.
class DashboardSessionUser {
  const DashboardSessionUser({
    required this.userId,
    required this.sessionCount,
  });

  final String userId;
  final int sessionCount;

  factory DashboardSessionUser.fromJson(Map<String, dynamic> json) {
    return DashboardSessionUser(
      userId: json['user_id'] as String,
      sessionCount: json['session_count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'session_count': sessionCount,
  };
}

/// What `_jwt` can honestly answer about sessions.
///
/// **The table has three columns — `id`, `user_id`, `expires_at` — and that is
/// the whole budget.** There is no `created_at`, no device, no IP and no
/// last-seen, so sessions-over-time, "signed in from", and idle-session
/// reporting are not derivable here and must not be rendered as if they were.
/// Every field below is a projection of those three columns and nothing else.
///
/// One consequence worth saying out loud: [expiringWithinHour] is the closest
/// thing to a churn signal available. Without `created_at`, a spike in new
/// sign-ins is invisible until those tokens approach their own expiry.
class DashboardSessions {
  const DashboardSessions({
    required this.active,
    required this.expiringWithinHour,
    required this.distinctUsers,
    required this.topUsers,
  });

  /// Sessions whose `expires_at` is still in the future.
  ///
  /// Not the same as the row count: `_delete_expired_jwts` only sweeps at 04:00,
  /// so between sweeps the table holds expired rows that are not sessions. A
  /// count that skipped the comparison would report the backlog as people
  /// signed in.
  final int active;

  /// Active sessions that expire within the next hour.
  ///
  /// A subset of [active], never disjoint from it.
  final int expiringWithinHour;

  /// Distinct `user_id` values across the [active] sessions.
  ///
  /// Reported next to [active] rather than instead of it: the gap between the
  /// two is the multi-device story, and either number alone hides it.
  final int distinctUsers;

  /// Users holding the most live sessions, most first.
  final List<DashboardSessionUser> topUsers;

  factory DashboardSessions.fromJson(Map<String, dynamic> json) {
    return DashboardSessions(
      active: json['active'] as int,
      expiringWithinHour: json['expiring_within_hour'] as int,
      distinctUsers: json['distinct_users'] as int,
      topUsers: [
        for (final user in json['top_users'] as List)
          DashboardSessionUser.fromJson(Map<String, dynamic>.from(user as Map)),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'active': active,
    'expiring_within_hour': expiringWithinHour,
    'distinct_users': distinctUsers,
    'top_users': [for (final user in topUsers) user.toJson()],
  };
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.requestCount24h,
    required this.errorCount24h,
    required this.activeSessions,
    required this.requestBuckets,
    required this.pushQueue,
    required this.sessions,
    this.p95ResponseMs,
  });

  final int requestCount24h;
  final int errorCount24h;

  /// The same number as [DashboardSessions.active], kept as a top-level field
  /// because it is part of the published wire shape (`tool/ci/e2e/drive.dart`
  /// asserts the key). The engine assigns both from one query so they cannot
  /// drift apart.
  final int activeSessions;

  final int? p95ResponseMs;
  final List<DashboardRequestBucket> requestBuckets;

  /// The `_push_jobs` queue the `_drain_push_jobs` cron works through.
  final DashboardPushQueue pushQueue;

  /// What `_jwt`'s three columns can answer about sessions.
  final DashboardSessions sessions;

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) {
    return DashboardMetrics(
      requestCount24h: json['request_count_24h'] as int,
      errorCount24h: json['error_count_24h'] as int,
      activeSessions: json['active_sessions'] as int,
      p95ResponseMs: json['p95_response_ms'] as int?,
      requestBuckets: [
        for (final bucket in json['request_buckets'] as List)
          DashboardRequestBucket.fromJson(
            Map<String, dynamic>.from(bucket as Map),
          ),
      ],
      pushQueue: DashboardPushQueue.fromJson(
        Map<String, dynamic>.from(json['push_queue'] as Map),
      ),
      sessions: DashboardSessions.fromJson(
        Map<String, dynamic>.from(json['sessions'] as Map),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'request_count_24h': requestCount24h,
    'error_count_24h': errorCount24h,
    'active_sessions': activeSessions,
    'p95_response_ms': p95ResponseMs,
    'request_buckets': [for (final bucket in requestBuckets) bucket.toJson()],
    'push_queue': pushQueue.toJson(),
    'sessions': sessions.toJson(),
  };
}
