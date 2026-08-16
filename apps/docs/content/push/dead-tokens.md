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
| **A real app, uninstalled from a real device** | **404** | **`NOT_FOUND`** | **pruned** |
| A malformed token | 400 | `INVALID_ARGUMENT` | pruned |
| An iOS token whose app has no usable APNs credential | 401 | `UNAUTHENTICATED` + `THIRD_PARTY_AUTH_ERROR` | transient, **not** pruned |
| A key without FCM permission | 403 | `PERMISSION_DENIED` | job fails, **nothing pruned** |
| No credentials at all | 401 | `UNAUTHENTICATED` | job fails, **nothing pruned** |

`NOT_FOUND` is the one worth noticing, and the second row is why. An app was installed on a physical device, issued a token, sent to successfully, then uninstalled — and the very next send came back `NOT_FOUND`, not `UNREGISTERED`. The documentation leads you to `UNREGISTERED`; handling only that would classify every dead token as *transient*, so it would be retried forever and pruned never — the exact failure this page exists to prevent, reached by following the docs correctly. Both are handled.

Note also that `INVALID_ARGUMENT` is what FCM returns for a bad **message**, not only a bad token. That ambiguity is why a batch in which *every* recipient comes back `INVALID_ARGUMENT` fails the job instead of pruning: hundreds of simultaneous dead tokens is vanishingly unlikely, one malformed notification is not.

### What APNs returns

When iOS goes direct, Apple answers with a `reason` string rather than a status, and the same status carries both kinds of problem — `400` is a malformed token *and* a malformed payload. So the reason is what Zonai reads.

| `reason` | Result |
|---|---|
| `Unregistered`, `BadDeviceToken` | pruned |
| `PayloadTooLarge`, `BadCollapseId`, `MissingTopic`, `TopicDisallowed` | pruned as a bad message |
| **`DeviceTokenNotForTopic`** | **transient, never pruned** |
| `TooManyRequests`, `ServiceUnavailable`, `InternalServerError` | transient |
| `InvalidProviderToken`, `ExpiredProviderToken` | job fails, **nothing pruned** |
| anything unrecognised | transient |

`DeviceTokenNotForTopic` is the one to understand. Measured against live APNs: a topic your team does not own answers `TopicDisallowed`, while a topic it *does* own paired with a token from a different app answers this. So it means your **`bundleId` disagrees with the app** — a config fault, and a uniform one. Every iOS recipient returns it at once, so reading it as "these devices are dead" would empty your table over a typo. Zonai counts it transient and names the field.

The rest of this table is transcribed from Apple's documentation and has *not* all been observed. The FCM table above was written the same way and was wrong three times, so anything unrecognised is treated as transient on purpose: an unknown reason costs a retry, and guessing permanent costs a device that never hears from your app again.

## Credentials are never a token's fault

A `401` or `403` is usually neither. It is a statement about your credentials, not about any token, so the job fails and **nothing is pruned** — classifying it per-token would clear every token in the batch over a config mistake.

**The exception is `THIRD_PARTY_AUTH_ERROR`**, and it is worth understanding because it looks identical from the status alone. FCM returns `401 UNAUTHENTICATED` with that `errorCode` when it cannot obtain a usable APNs credential **for that app** — the caller's credentials are fine and only one platform is broken. Zonai reads `error.details[].errorCode` to tell the two apart.

Measured, because the obvious reading is too narrow: the same project and key answered `401` for an app whose bundle id was not a registered App ID, and `200` for one that was. So a missing or expired key is only one cause; an unregistered or non-push-enabled bundle produces it just as well. Check both before assuming the key.

Those recipients are counted as **transient failures**: the batch keeps going, every Android recipient is still delivered to, and the job does not fail. And they are never pruned — the device token is perfectly valid, so clearing it would delete every iOS registration you have over a lapsed credential, irreversibly, at the exact moment someone is renewing it. Once the key is uploaded, the next fan-out reaches them.

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
