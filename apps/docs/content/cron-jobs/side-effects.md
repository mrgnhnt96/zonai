---
title: Side Effects in Cron Jobs
description: Using get, mutate, email, and push from inside a cron job.
---

Cron jobs have access to the same side-effect APIs as extension hooks: `get`, `mutate`, `email`, `push`, and `logger`. They all run as the `CronJwt` system identity, so you never pass a JWT. The job's `run()` runs in the crons worker process, which has no direct access to SQLite. Every read and write goes back to the server and through the normal API pipeline.

## get

Read rows from any table. Returns untyped maps:

```dart in:cron-run
final expiredRows = await get.many(
  tableName: 'subscriptions',
  where: Lt('expires_at', DateTime.now()),
  limit: 100,
) ?? [];
```

Reads run immediately: `get` is awaited and returns the rows as they are now. They carry the CronJwt system identity, the same as `mutate` below, so you do not pass a JWT. Rules and row rules on the table you read are evaluated against it, so a table that denies anonymous reads still answers a cron. Passing an explicit `jwt:` overrides that when a job needs to read as someone else.

See [Side Effects: get](/extensions/side-effects-get) for full documentation.

## mutate

Insert, update, or delete rows. In cron jobs `mutate` calls go through the full pipeline (rules, operations, extensions) as `CronJwt`:

```dart in:cron-run
mutate.delete.many(
  tableName: 'old_logs',
  where: Lt('created_at', cutoff),
);

mutate.update.one(
  table: 'users',
  updates: [Update.column('status', .literal('inactive'))],
  where: Eq('id', userId),
);
```

**Writes are queued, not awaited.** They are committed after `run()` finishes, so a `get` later in the same run does not see them. `mutate.create`, `mutate.update` and `mutate.delete` return `void`, which means a job cannot see how many rows it changed or whether the write succeeded. If committing fails, the server logs the error; the job's `_cron_jobs` row is not marked failed. Treat the log line at the end of `run()` as a record that the job *ran*, not that it changed anything.

Each queued write fires the target table's extension hooks, and those hooks can queue more writes, up to the same [chain limit](/extensions/side-effects-mutate#the-chain-limit) as requests. The cron tick itself fires no extension hooks.

For a large delete on your own tables, page the work (a `limit:` per call across runs) rather than issuing one unbounded delete. `mutate.delete` reads every matching row first and checks row rules one row at a time.

See [Side Effects: mutate](/extensions/side-effects-mutate) for full documentation.

### mutate.purge (internal tables only)

Zonai's built-in retention jobs use `mutate.purge`, a bulk `DELETE ... WHERE` that returns the number of rows removed:

```dart in:cron-run
final removed = await mutate.purge(
  tableName: '_log',
  where: Lt('timestamp', cutoff),
);

logger.info('Deleted $removed log records older than $cutoff');
```

It skips the work `mutate.delete` does: it reads no rows first, runs no per-row rule checks and fires no extension hooks. Because it skips rules, the server enforces two limits:

1. **The table must be one of Zonai's internal tables.** Application tables are never purgeable. `_photos` is excluded too, because deleting a photo row must also delete its file.
2. **The caller must be an admin identity.** `CronJwt` is one.

Anything else is refused with an access-denied error. For your own tables, use `mutate.delete`.

## email

Send transactional email using custom templates or the built-in helpers:

```dart in:cron-run
email.send(Email(
  to: EmailAddress(address: user['email'] as String),
  subject: 'Your subscription is expiring',
  template: 'subscription_expiry',
  variables: {'days': daysLeft},
));
```

See [Side Effects: email](/extensions/side-effects-email) for full documentation.

## push

Send a push notification to every row a query matches. Unlike `mutate`, `push` is awaited and returns a job id. That id means the job was recorded, not that anything was delivered. The fan-out runs on the server afterwards and keeps going after the cron run ends. Query `_push_jobs` with the id to follow its progress.

See [Side Effects: push](/extensions/side-effects-push) for full documentation.

## logger

Write log lines at debug, info, warn or error level. They are forwarded to the server log (and the dev TUI):

```dart in:cron-run
logger.info('Processed ${rows.length} rows');
logger.warn('Found ${stale.length} stale subscriptions');
logger.error('Failed to send digest: $error');
```

## Complete Example

```dart in:project-file
final class ExpiryNotificationJob extends CronJob {
  ExpiryNotificationJob()
    : super(
        name: 'expiry-notifications',
        schedule: Schedule.parse('0 9 * * *'),
      );

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().add(const Duration(days: 7));
    final expiring = await get.many(
      tableName: 'subscriptions',
      where: And([Lt('expires_at', cutoff), Eq('notified', false)]),
    ) ?? [];

    logger.info('Sending expiry notices to ${expiring.length} users');

    for (final row in expiring) {
      email.send(Email(
        to: EmailAddress(address: row['email'] as String),
        subject: 'Your subscription expires soon',
        template: 'expiry_notice',
        variables: {'expires_at': row['expires_at']},
      ));

      mutate.update.one(
        table: 'subscriptions',
        updates: [Update.column('notified', .literal(true))],
        where: Eq('id', row['id']!),
      );
    }
  }
}

ExpiryNotificationJob main() => ExpiryNotificationJob();
```
