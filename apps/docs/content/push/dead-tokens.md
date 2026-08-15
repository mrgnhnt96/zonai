---
title: Dead Tokens
description: How Zonai prunes a token FCM has rejected for good, the hook that fires first, and why a timeout is not a death.
---

When FCM reports a token permanently rejected — the app was uninstalled, or the registration rotated — Zonai tells your app, then acts on it.

## The policy

| `onPermanentRejection` | Effect |
|---|---|
| `clearColumn` | **Default.** Sets the token column to `NULL`. The row stays. |
| `deleteRow` | Deletes the row. Opt-in. |
| `none` | Zonai does nothing. `onPushRejected` is the only signal — and it still fires. |

### Why `clearColumn` is the default

The failure modes are not symmetric. Nothing stops you putting a token column on `users` rather than a dedicated table, and Zonai cannot tell the difference. Under a `deleteRow` default, a wiped phone would delete a user account — unrecoverable, and caused by a setting nobody chose.

Under `clearColumn`, the worst case is a row with a null token: inert, skipped by every fan-out, and cleanable whenever you like.

A destructive default has to be earned. This one cannot be.

## Only permanent rejections prune

A timeout, a `503`, or a quota rejection is a **transient failure**. It is counted on the job row, retried within the batch, and never touches your row.

A token that timed out is not a token that is dead. Keeping those two apart is most of the reason this feature lives in the framework instead of in your hook — the distinction is invisible unless you go looking for it, and getting it wrong deletes live registrations.

Permanent means `UNREGISTERED`, `NOT_FOUND` or `INVALID_ARGUMENT`, and nothing else. An unrecognised status from FCM is treated as transient on purpose: guessing transient costs a retry, and guessing permanent costs a device that never hears from your app again.

### What FCM actually returns

Verified against live FCM rather than taken from the documentation:

| What was sent | HTTP | `error.status` | Result |
|---|---|---|---|
| A well-formed token FCM never issued | 404 | `NOT_FOUND` | pruned |
| A malformed token | 400 | `INVALID_ARGUMENT` | pruned |
| A key without FCM permission | 403 | `PERMISSION_DENIED` | job fails, **nothing pruned** |
| No credentials at all | 401 | `UNAUTHENTICATED` | job fails, **nothing pruned** |

`NOT_FOUND` is the one worth noticing. The documentation leads you to `UNREGISTERED`, and handling only that would classify an unknown token as *transient* — so it would be retried forever and never pruned, which is the exact failure this whole page exists to prevent. Both are handled.

Note also that `INVALID_ARGUMENT` is what FCM returns for a bad **message**, not only a bad token. That ambiguity is why a batch in which *every* recipient comes back `INVALID_ARGUMENT` fails the job instead of pruning: hundreds of simultaneous dead tokens is vanishingly unlikely, one malformed notification is not.

A `401` or `403` is neither. It is a statement about your credentials, not about any token, so the job fails and **nothing is pruned** — classifying it per-token would clear every token in the batch over a config mistake.

## The hook

```dart in:push-device-tokens
final class DeviceTokenExtension extends Extension<DeviceToken> {
  DeviceTokenExtension() : super(deviceTokens);

  @override
  Future<void> onPushRejected(
    DeviceToken row,
    String token,
    PushRejectionReason reason,
    Jwt? jwt,
  ) async {
    logger.info('device ${row.id} unregistered ($reason)');
  }
}

final deviceTokens = table('device_tokens', DeviceTokenTable.new);

final class DeviceTokenTable extends Table<DeviceToken> {
  DeviceTokenTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UsersId.new,
        generate: UsersId.generate,
      ),
      userId = $.text('user_id', (s) => s.userId),
      token = $.deviceToken('token', (s) => s.token),
      platform = $.text('platform', (s) => s.platform);

  @override
  DeviceToken fromRow(RowReader read) => DeviceToken(
    id: read(id),
    userId: read(userId),
    token: read(token),
    platform: read(platform),
  );

  final IdColumn<UsersId> id;
  final TextColumn userId;
  final ColumnType<String?> token;
  final TextColumn platform;
}
```

`onPushRejected` fires **before** the prune, so `row` is intact when you see it — under `clearColumn` the token has not been nulled yet, and under `deleteRow` the row still exists. A hook handed an already-cleared row could not tell which user it belonged to.

It fires under **all three** settings, `none` included. That is what makes `none` a usable choice rather than a silent one: switching Zonai's pruning off leaves your app informed rather than blind.

A hook that throws is logged and does not stop the prune or the fan-out. The token is dead either way, and a job that stalled because one app callback threw would stop notifying everyone else.

## A steadily climbing rejection count is normal

`permanently_rejected` on the jobs collection is, in aggregate, your uninstall rate. It is supposed to be non-zero, and it is why pruning exists — without it, every fan-out would spend part of its quota on devices that no longer exist.
