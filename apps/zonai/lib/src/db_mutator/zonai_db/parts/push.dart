part of zonai_db;

/// What one drain pass reports back.
typedef _DrainPushResult = ({
  int jobsAdvanced,
  int jobsCompleted,
  int sent,
  int permanentlyRejected,
  int transientlyFailed,
  String? skipped,
});

const _emptyDrain = (
  jobsAdvanced: 0,
  jobsCompleted: 0,
  sent: 0,
  permanentlyRejected: 0,
  transientlyFailed: 0,
  skipped: null,
);

/// Unfinished jobs a single drain pass will look at.
///
/// A bound rather than "all of them" because a pass holds the drain lock:
/// with a thousand queued jobs, an unbounded pass would keep the lock for as
/// long as it took to finish every one of them, and the enqueue-time kick
/// would never get a turn. Jobs beyond this are picked up by the next pass,
/// which is a minute away at most.
const _maxJobsPerDrain = 16;

/// Batches one job may commit within a single pass.
///
/// Without it, one large fan-out starves every other job in the queue: the
/// pass would page through a hundred thousand recipients before looking at
/// the job enqueued a second later. The cursor makes stopping free — the next
/// pass resumes exactly where this one stopped.
const _maxBatchesPerJobPerDrain = 20;

extension _PushX on ZonaiDb {
  /// Records a fan-out and hands back its id.
  ///
  /// Returns null — rather than throwing — when the project has no
  /// `AppConfig.push`. A missing config must be loud and must not throw; the
  /// worker turns the null into a `StateError` at the call site, where the
  /// stack still points at the code that asked to send.
  Future<PushJobId?> _enqueuePush({
    required PushMessage message,
    required String table,
    required String column,
    required Where? where,
    required Jwt? jwt,
  }) async {
    // Gate one: an admin identity. `CronJwt` qualifies, so a scheduled job
    // needs no special-casing. Enforced here, host-side, rather than trusted
    // from the caller — the request arrives over IPC from a worker process.
    if (jwt?.admin.isAdmin != true) {
      throw TableAccessDeniedException(table: table, operation: 'push');
    }

    final config = await configResolver.resolve();
    if (config.push == null) {
      logger.warn(
        'Cannot send a push notification because AppConfig.push is not '
        'configured. Nothing was enqueued.',
      );
      return null;
    }

    // Gate two: the message has to be small enough to send. Checked before
    // anything is written, because FCM answers an over-limit payload with
    // `INVALID_ARGUMENT` -- the same status a dead token gets -- so a job
    // that got this far would look exactly like every recipient
    // unregistering at once.
    if (message.tooLargeReason case final reason?) {
      throw PushTargetException(reason);
    }

    // Gate three: the named column must actually be a `deviceToken` column.
    // This is what stops `push` being turned into a way to read a column the
    // caller could not otherwise read — the fan-out projects only the primary
    // key and this column, and this check is what makes "this column" mean
    // something.
    await _resolveDeviceTokenTarget(table: table, column: column);

    final entry = PushJobEntry.create(
      message: message,
      targetTable: table,
      targetColumn: column,
      where: where,
    );

    final db = await open();
    await db.insert(into: pushJobs).values([entry]);

    // Start immediately rather than waiting for `_drain_push_jobs` to come
    // round: a notification that waits up to a minute for a cron tick is a
    // notification nobody will call timely. Unawaited on purpose — `push`
    // promises the job is *recorded*, not that it has run, and awaiting the
    // fan-out here would undo the entire reason it is a job.
    unawaited(
      _drainPushJobs().catchError((Object e, StackTrace s) {
        logger.error('Push drain failed after enqueue', e, s);
        return _emptyDrain;
      }),
    );

    return entry.id;
  }

  /// Where a job's recipients live, verified.
  ///
  /// Throws rather than returning null for every failure: each of these is a
  /// programming error in the app's own `push` call, and a fan-out that
  /// silently sent to nobody would be indistinguishable from one whose
  /// recipients had all uninstalled.
  Future<({String primaryKey, String tokenColumn})> _resolveDeviceTokenTarget({
    required String table,
    required String column,
  }) async {
    final shapes = await schemaShapes();
    final shape = shapes[table];

    if (shape == null) {
      throw PushTargetException('No collection named "$table"');
    }

    final columnShape = shape.columnNamed(column);
    if (columnShape == null) {
      throw PushTargetException('"$table" has no column "$column"');
    }

    if (columnShape.kind != ColumnShapeKind.deviceToken) {
      throw PushTargetException(
        '"$table"."$column" is a ${columnShape.kind.toJson()} column, not a '
        'deviceToken column. Declare it with `\$.deviceToken(...)` so Zonai '
        'can recognise it — push will not read a column it was not pointed '
        'at.',
      );
    }

    final primaryKey = _primaryKeyColumnName(shape);
    if (primaryKey == null) {
      throw PushTargetException(
        '"$table" has no primary key, so a fan-out over it cannot be '
        'checkpointed. Keyset pagination needs a stable column to resume '
        'from; without one a crash would restart from the top and re-notify '
        'everyone it had already reached.',
      );
    }

    return (primaryKey: primaryKey, tokenColumn: columnShape.name);
  }

  /// Advances every unfinished fan-out.
  ///
  /// Passes are **chained**, not skipped. Two running at once would read the
  /// same batch from the same cursor and send it twice, so they must
  /// serialize — but a second caller that returned an immediate zero instead
  /// of waiting would be lying twice over: it would report "nothing moved"
  /// while a pass was moving things, and it would return before the job the
  /// caller just enqueued had been looked at. Chaining means every caller
  /// gets a pass that *started after their call*, which is the only answer
  /// that means anything.
  ///
  /// In-process is the right scope for the chain: the job table is only ever
  /// drained by the host, and there is one host.
  Future<_DrainPushResult> _drainPushJobs() {
    final previous = _pushDrain;

    final next = () async {
      if (previous != null) {
        // A failed pass must not poison the queue for the next one. Its own
        // caller already saw the error, and each job records its own failure
        // on its own row.
        try {
          await previous;
        } catch (_) {}
      }
      return await _drainPushJobsLocked();
    }();

    _pushDrain = next;
    return next;
  }

  Future<_DrainPushResult> _drainPushJobsLocked() async {
    final config = (await configResolver.resolve()).push;
    if (config == null) {
      // Not an error: a project that never configured push has no jobs, and
      // the cron runs every minute regardless. Named rather than reported as
      // a quiet zero, so "nothing is being delivered" is answerable.
      return (
        jobsAdvanced: 0,
        jobsCompleted: 0,
        sent: 0,
        permanentlyRejected: 0,
        transientlyFailed: 0,
        skipped: 'AppConfig.push is not configured',
      );
    }

    final jobs = await _pendingPushJobs();
    if (jobs.isEmpty) return _emptyDrain;

    var jobsAdvanced = 0;
    var jobsCompleted = 0;
    var sent = 0;
    var permanentlyRejected = 0;
    var transientlyFailed = 0;

    for (final job in jobs) {
      final ({
        int batches,
        bool completed,
        int sent,
        int permanentlyRejected,
        int transientlyFailed,
      })
      result;
      try {
        result = await _advancePushJob(job, config);
      } catch (e, stack) {
        // One job's failure must not abort the pass. A job whose target
        // table has become unreadable would otherwise stop every other job
        // behind it in the queue, permanently, once a minute.
        logger.error('Push job ${job.id.value} could not advance', e, stack);
        await _failPushJob(job, '$e');
        continue;
      }

      if (result.batches > 0) jobsAdvanced++;
      if (result.completed) jobsCompleted++;
      sent += result.sent;
      permanentlyRejected += result.permanentlyRejected;
      transientlyFailed += result.transientlyFailed;
    }

    // A job that advanced without finishing hit this pass's batch ceiling,
    // which exists to stop one large fan-out starving the queue behind it --
    // not to throttle it. Without this, a hundred-thousand-recipient job
    // would advance 10,000 per pass and then wait for the next minute
    // boundary, turning a bound meant to keep the queue fair into a silent
    // rate limit of its own. Chaining another pass lets it continue at full
    // speed while still yielding between passes, so a job enqueued a second
    // ago gets its turn rather than queueing behind the whole fan-out.
    if (jobsAdvanced > jobsCompleted) {
      unawaited(
        _drainPushJobs().catchError((Object e, StackTrace s) {
          logger.error('Push drain continuation failed', e, s);
          return _emptyDrain;
        }),
      );
    }

    return (
      jobsAdvanced: jobsAdvanced,
      jobsCompleted: jobsCompleted,
      sent: sent,
      permanentlyRejected: permanentlyRejected,
      transientlyFailed: transientlyFailed,
      skipped: null,
    );
  }

  /// The oldest unfinished jobs.
  ///
  /// Built as SQL directly rather than through the operations worker:
  /// `_push_jobs` is an internal table whose schema Zonai owns statically, so
  /// a worker round trip would buy nothing and would make the drain
  /// untestable without a compiled project. The same reasoning as
  /// `_photoPage`.
  Future<List<PushJobEntry>> _pendingPushJobs() async {
    final db = await open();
    return await db
        .select()
        .from(pushJobs)
        .where(
          pushJobs.status.equals(PushJobStatus.pending) |
              pushJobs.status.equals(PushJobStatus.running),
        )
        .orderBy({pushJobs.createdAt: Order.asc})
        .limit(_maxJobsPerDrain);
  }

  /// Pages [job] forward, committing each batch before starting the next.
  Future<
    ({
      int batches,
      bool completed,
      int sent,
      int permanentlyRejected,
      int transientlyFailed,
    })
  >
  _advancePushJob(PushJobEntry job, PushConfig config) async {
    var cursor = job.cursor;
    var batches = 0;
    var completed = false;

    // Two sets of counters, and the split is load-bearing. The `total*` ones
    // are written to the job row, so they must resume from what is already
    // there — a job that advanced 400 recipients yesterday and 100 today
    // reads 500, not 100. The pass-local ones are what the drain reports,
    // because "what moved this pass" is the number that distinguishes a
    // working queue from a stuck one, and a running total never does.
    var totalSent = job.delivered;
    var totalPermanentlyRejected = job.permanentlyRejected;
    var totalTransientlyFailed = job.transientlyFailed;

    var sent = 0;
    var permanentlyRejected = 0;
    var transientlyFailed = 0;

    final ({String primaryKey, String tokenColumn}) target;
    try {
      target = await _resolveDeviceTokenTarget(
        table: job.targetTable,
        column: job.targetColumn,
      );
    } catch (e) {
      // The schema moved under a recorded job — the token column was renamed
      // or dropped between enqueue and drain. Nothing here can be retried
      // into success, so fail the job loudly rather than retrying it every
      // minute forever.
      await _failPushJob(job, 'target no longer valid: $e');
      return (
        batches: 0,
        completed: false,
        sent: 0,
        permanentlyRejected: 0,
        transientlyFailed: 0,
      );
    }

    final message = job.pushMessage;

    while (batches < _maxBatchesPerJobPerDrain) {
      final batch = await _pushRecipientBatch(
        job: job,
        target: target,
        after: cursor,
        limit: config.batchSize,
      );

      if (batch.isEmpty) {
        completed = true;
        break;
      }

      final List<PushOutcome> outcomes;
      try {
        outcomes = await _sendPushBatch(
          message: message,
          tokens: [for (final row in batch) row.token],
          config: config,
        );
      } on PushTransportException catch (e) {
        // Not about any one token: bad credentials, an unreachable auth
        // endpoint. The cursor stays exactly where it was, so the next drain
        // re-reads this batch rather than skipping past it.
        await _failPushJob(job, '$e');
        break;
      }

      // FCM answers a bad *token* and a bad *message* with the same
      // `INVALID_ARGUMENT`. The second fails identically for every recipient,
      // so taking it at face value prunes the whole batch because the author
      // wrote one notification wrong — under `deleteRow`, the whole table.
      //
      // Every token in a batch going individually bad at the same instant is
      // not a real failure mode; one malformed message is. So a *unanimous*
      // INVALID_ARGUMENT is read as a statement about the message: the job
      // fails, the cursor stays put, and nothing is pruned. Both readings are
      // served by that — if the tokens really were all bad, the operator is
      // told rather than having the rows disappear.
      //
      // Deliberately narrow. Unanimous `UNREGISTERED` is left alone: an old
      // cohort whose app was uninstalled genuinely is a full batch of dead
      // tokens, and refusing to prune those leaves a table that never drains.
      // And it needs more than one recipient to mean anything — at a batch of
      // one there is nothing to be unanimous about, and the blast radius is
      // the single token that ordinary pruning would clear anyway.
      if (batch.length > 1 &&
          outcomes.every(
            (o) =>
                o is PushPermanentlyRejected &&
                o.reason == PushRejectionReason.invalidArgument,
          )) {
        await _failPushJob(
          job,
          'every recipient in a batch of ${batch.length} was rejected with '
          'INVALID_ARGUMENT, which almost always means the message is '
          'malformed rather than the tokens. Nothing was pruned. Check the '
          "message's size and data keys.",
        );
        break;
      }

      final byToken = <String, PushOutcome>{
        for (final outcome in outcomes) outcome.token: outcome,
      };

      final rejected = <({String primaryKey, String token, PushRejectionReason reason})>[];
      for (final row in batch) {
        switch (byToken[row.token]) {
          case PushDelivered():
            sent++;
            totalSent++;
          case PushPermanentlyRejected(:final reason):
            permanentlyRejected++;
            totalPermanentlyRejected++;
            rejected.add((
              primaryKey: row.primaryKey,
              token: row.token,
              reason: reason,
            ));
          case PushTransientlyFailed() || null:
            transientlyFailed++;
            totalTransientlyFailed++;
        }
      }

      // The hook fires BEFORE the prune, and before the transaction, so the
      // app sees the row intact. It is also an IPC round trip to the
      // extensions worker, which has no business inside a write transaction.
      for (final row in rejected) {
        await _notifyPushRejected(
          job: job,
          target: target,
          primaryKey: row.primaryKey,
          token: row.token,
          reason: row.reason,
        );
      }

      cursor = batch.last.primaryKey;
      batches++;

      // The prune and the cursor advance commit together. That is the whole
      // checkpointing design in one statement: a crash anywhere before this
      // resumes from the previous batch boundary, and a crash after it never
      // re-sends what this batch already sent.
      await _commitPushBatch(
        job: job,
        target: target,
        cursor: cursor,
        rejected: rejected,
        delivered: totalSent,
        permanentlyRejected: totalPermanentlyRejected,
        transientlyFailed: totalTransientlyFailed,
        config: config,
      );

      // A short batch means the recipient set is drained. Anything else would
      // be another query returning nothing.
      if (batch.length < config.batchSize) {
        completed = true;
        break;
      }
    }

    if (completed) {
      await _finishPushJob(job, cursor);
    }

    return (
      batches: batches,
      completed: completed,
      sent: sent,
      permanentlyRejected: permanentlyRejected,
      transientlyFailed: transientlyFailed,
    );
  }

  /// One page of recipients: **the primary key and the token column, and
  /// nothing else.**
  ///
  /// The projection is a security property, not an optimisation. `push` takes
  /// a caller-supplied `where` and runs it with per-row rules bypassed; if it
  /// also selected `*`, it would be a way to read any column of any table an
  /// admin identity could name. It selects two columns, both of which the
  /// caller already had to name, and the token one had to be declared a
  /// `deviceToken` column to be nameable at all.
  ///
  /// Keyset pagination, never `OFFSET`. `OFFSET` degrades linearly across the
  /// scan and — worse — silently skips or repeats rows when the table is
  /// written to mid-scan, which it will be: devices register while a fan-out
  /// is running.
  Future<List<({String primaryKey, String token})>> _pushRecipientBatch({
    required PushJobEntry job,
    required ({String primaryKey, String tokenColumn}) target,
    required String? after,
    required int limit,
  }) async {
    final table = _escapeIdentifier(job.targetTable);
    final pk = _escapeIdentifier(target.primaryKey);
    final tokenColumn = _escapeIdentifier(target.tokenColumn);

    final values = <Object?>[];
    final buffer = StringBuffer()
      ..write('SELECT "$pk" AS pk, "$tokenColumn" AS token FROM "$table" ')
      ..write('WHERE "$tokenColumn" IS NOT NULL AND "$tokenColumn" != \'\'');

    if (job.where case final where?) {
      final (sql, params) = where.sql(job.targetTable);
      buffer.write(' AND ($sql)');
      values.addAll(params);
    }

    if (after != null) {
      buffer.write(' AND "$pk" > ?');
      values.add(after);
    }

    buffer.write(' ORDER BY "$pk" ASC LIMIT $limit');

    final (error, result) = await _execute((buffer.toString(), values));
    if (error != null || result == null) {
      throw PushTargetException(
        'Could not read recipients from "${job.targetTable}": $error',
      );
    }

    return [
      for (final row in result.rows)
        if (row.toMap() case {'pk': final Object pk, 'token': final String token}
            when token.isNotEmpty)
          (primaryKey: '$pk', token: token),
    ];
  }

  /// Sends one batch, retrying only what failed transiently.
  ///
  /// Retries the *transient subset*, not the batch: re-sending a token that
  /// already succeeded would be a duplicate this layer can avoid for free,
  /// unlike the crash-resume duplicate it cannot.
  Future<List<PushOutcome>> _sendPushBatch({
    required PushMessage message,
    required List<String> tokens,
    required PushConfig config,
  }) async {
    final settled = <String, PushOutcome>{};
    var pending = tokens;

    for (var attempt = 0; attempt < config.maxAttemptsPerBatch; attempt++) {
      if (attempt > 0) {
        // Exponential backoff. FCM quotas are per-project and per-minute, so
        // a retry that arrives immediately meets the same wall the first
        // attempt did.
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }

      final outcomes = await pushCourier.send(
        message,
        pending,
        config: config,
      );

      final retry = <String>[];
      for (final outcome in outcomes) {
        settled[outcome.token] = outcome;
        if (outcome is PushTransientlyFailed) retry.add(outcome.token);
      }

      if (retry.isEmpty) break;
      pending = retry;
    }

    return [
      for (final token in tokens)
        settled[token] ??
            PushTransientlyFailed(token: token, detail: 'no outcome recorded'),
    ];
  }

  /// Dispatches `onPushRejected` for one dead token.
  ///
  /// Reads the row back so the hook receives it whole. That read is the one
  /// place the fan-out looks at a column other than the key and the token,
  /// and it is bounded by the number of *dead* tokens in a batch rather than
  /// the batch size — which in a healthy deployment is nearly always zero.
  Future<void> _notifyPushRejected({
    required PushJobEntry job,
    required ({String primaryKey, String tokenColumn}) target,
    required String primaryKey,
    required String token,
    required PushRejectionReason reason,
  }) async {
    Map<String, Object?>? row;
    try {
      final operation = await _getOperation(
        ReadOperationRequest(
          table: job.targetTable,
          where: Eq(target.primaryKey, primaryKey),
          jwt: CronJwt(),
        ),
      );
      final (_, result) = await _execute((operation.query, operation.values));
      if (result != null && result.rows.isNotEmpty) {
        row = result.rows.first.toMap();
      }
    } catch (e) {
      logger.warn('Could not read row for onPushRejected: $e');
    }

    if (row == null) return;

    try {
      await _runExtension(
        PushRejectedExtensionRequest(
          table: job.targetTable,
          object: {
            for (final entry in row.entries) entry.key: entry.value,
          },
          token: token,
          reason: reason,
          jwt: CronJwt(),
        ),
      );
    } catch (e, stack) {
      // A throwing hook must not stop the prune, and must not stop the
      // fan-out. The token is dead either way, and a job that stalled because
      // one app callback threw would stop notifying everyone else.
      logger.error('onPushRejected threw for "${job.targetTable}"', e, stack);
    }
  }

  /// Commits one batch's outcome: the prunes, the counters and the cursor,
  /// in a single transaction.
  Future<void> _commitPushBatch({
    required PushJobEntry job,
    required ({String primaryKey, String tokenColumn}) target,
    required String cursor,
    required List<({String primaryKey, String token, PushRejectionReason reason})>
    rejected,
    required int delivered,
    required int permanentlyRejected,
    required int transientlyFailed,
    required PushConfig config,
  }) async {
    final statements = <(String, List<Object?>)>[
      ..._pruneStatements(
        job: job,
        target: target,
        rejected: rejected,
        config: config,
      ),
      (
        'UPDATE "${_escapeIdentifier(pushJobs.$.name)}" SET '
            '"${pushJobs.cursor.name}" = ?, '
            '"${pushJobs.status.name}" = ?, '
            '"${pushJobs.delivered.name}" = ?, '
            '"${pushJobs.permanentlyRejected.name}" = ?, '
            '"${pushJobs.transientlyFailed.name}" = ?, '
            '"${pushJobs.updatedAt.name}" = ? '
            'WHERE "${pushJobs.id.name}" = ?',
        [
          cursor,
          PushJobStatus.running.name,
          delivered,
          permanentlyRejected,
          transientlyFailed,
          DateTime.now().millisecondsSinceEpoch,
          job.id.value,
        ],
      ),
    ];

    await _executeAll(statements);
  }

  /// The prune, as SQL, per the configured policy.
  ///
  /// `none` yields nothing at all — not a no-op update. The hook has already
  /// fired by the time this is called, which is what makes `none` a usable
  /// choice rather than a silent one.
  List<(String, List<Object?>)> _pruneStatements({
    required PushJobEntry job,
    required ({String primaryKey, String tokenColumn}) target,
    required List<({String primaryKey, String token, PushRejectionReason reason})>
    rejected,
    required PushConfig config,
  }) {
    if (rejected.isEmpty) return const [];
    if (config.onPermanentRejection == OnPermanentRejection.none) {
      return const [];
    }

    final table = _escapeIdentifier(job.targetTable);
    final pk = _escapeIdentifier(target.primaryKey);
    final tokenColumn = _escapeIdentifier(target.tokenColumn);

    final keys = [for (final row in rejected) row.primaryKey];
    final placeholders = List.filled(keys.length, '?').join(', ');

    // The token is matched as well as the key. Between reading the batch and
    // committing it, the device may have re-registered and written a *new*
    // token into the same row — clearing it then would delete a live
    // registration because a dead one used to be there.
    final tokens = [for (final row in rejected) row.token];

    return switch (config.onPermanentRejection) {
      OnPermanentRejection.clearColumn => [
        (
          'UPDATE "$table" SET "$tokenColumn" = NULL '
              'WHERE "$pk" IN ($placeholders) '
              'AND "$tokenColumn" IN ($placeholders)',
          [...keys, ...tokens],
        ),
      ],
      OnPermanentRejection.deleteRow => [
        (
          'DELETE FROM "$table" '
              'WHERE "$pk" IN ($placeholders) '
              'AND "$tokenColumn" IN ($placeholders)',
          [...keys, ...tokens],
        ),
      ],
      OnPermanentRejection.none => const [],
    };
  }

  Future<void> _finishPushJob(PushJobEntry job, String? cursor) async {
    await _executeAll([
      (
        'UPDATE "${_escapeIdentifier(pushJobs.$.name)}" SET '
            '"${pushJobs.status.name}" = ?, '
            '"${pushJobs.cursor.name}" = ?, '
            '"${pushJobs.updatedAt.name}" = ? '
            'WHERE "${pushJobs.id.name}" = ?',
        [
          PushJobStatus.completed.name,
          cursor,
          DateTime.now().millisecondsSinceEpoch,
          job.id.value,
        ],
      ),
    ]);
  }

  Future<void> _failPushJob(PushJobEntry job, String error) async {
    logger.error('Push job ${job.id.value} failed: $error');

    await _executeAll([
      (
        'UPDATE "${_escapeIdentifier(pushJobs.$.name)}" SET '
            '"${pushJobs.status.name}" = ?, '
            '"${pushJobs.error.name}" = ?, '
            '"${pushJobs.updatedAt.name}" = ? '
            'WHERE "${pushJobs.id.name}" = ?',
        [
          PushJobStatus.failed.name,
          error,
          DateTime.now().millisecondsSinceEpoch,
          job.id.value,
        ],
      ),
    ]);
  }

  /// Runs [statements] as one transaction.
  ///
  /// [_execute] takes a single query, and the checkpoint needs several to
  /// land together — the prune and the cursor advance are only a checkpoint
  /// if they commit atomically.
  Future<void> _executeAll(List<(String, List<Object?>)> statements) async {
    if (statements.isEmpty) return;

    final db = await open();
    await db.transaction((tx) async {
      for (final (query, values) in statements) {
        await tx.execute(query, values);
      }
    });
  }
}

/// Rejects an identifier that could break out of its quotes.
///
/// Table and column names here are not free strings — they are resolved
/// against `schemaShapes()` before reaching any statement, so this cannot be
/// the only thing standing between a caller and injection. It is the second
/// one, and it is cheap.
String _escapeIdentifier(String identifier) => identifier.replaceAll('"', '""');
