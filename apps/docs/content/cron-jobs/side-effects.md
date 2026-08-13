---
title: Side Effects in Cron Jobs
description: Using get, mutate, and email from inside a cron job.
---

Cron jobs have access to the same side-effect APIs as extension hooks: `get`, `mutate`, `email`, and `logger`.

## get

Read rows from any table. Returns untyped maps:

```dart in:cron-run
final expiredRows = await get.many(
  tableName: 'subscriptions',
  where: Lt('expires_at', DateTime.now()),
  limit: 100,
) ?? [];
```

See [Side Effects: get](/extensions/side-effects-get) for full documentation.

## mutate

Insert, update, or delete rows. In cron jobs `mutate` calls go through the full pipeline (rules, operations, extensions) using the CronJwt system identity:

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

See [Side Effects: mutate](/extensions/side-effects-mutate) for full documentation.

## email

Send transactional email using built-in helpers or custom templates:

```dart in:cron-run
email.send.loginNotice(
  EmailAddress(address: admin['email'] as String),
  table: 'admins',
);

email.send(Email(
  to: EmailAddress(address: user['email'] as String),
  subject: 'Your subscription is expiring',
  template: 'subscription_expiry',
  variables: {'days': daysLeft},
));
```

See [Side Effects: email](/extensions/side-effects-email) for full documentation.

## logger

Write structured log entries visible in server output and the `_log` table:

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
