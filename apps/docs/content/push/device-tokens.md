---
title: Device Tokens
description: The deviceToken column type, the platform column that routes a recipient, and why the table they live on is your decision rather than Zonai's.
---

A `deviceToken` column is how Zonai finds recipients. It is a semantic column type like `photo()` or `email()` — Zonai recognises it across every collection, and declaring one is what makes a column nameable by `push` at all.

```dart in:push-device-tokens
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

final deviceTokens = table('device_tokens', DeviceTokenTable.new);
```

## Two properties are load-bearing

**The token column must be nullable.** The default pruning policy writes `NULL` into it when FCM reports the token dead. A non-nullable column makes the framework's own default fail.

**The table must have a primary key.** Zonai pages by it, and the cursor it saves is what lets a fan-out resume instead of restarting from the top. A table without one is refused, with a message saying exactly that.

Everything else is yours: the table's name, whether there is a `user_id`, what else lives on the row. Zonai reads exactly one column and writes exactly one column.

## The platform column

A token is an opaque string, and FCM and APNs issue strings that look broadly alike. Nothing about the value says which service to send it to, and guessing from its shape is the tempting mistake: it works until an SDK version changes the format, and then it fails silently, per-device, in production.

So the app says. Store it in an ordinary column — there is no special column type — and name that column when you send:

```dart no-analyze
platformColumn: 'platform',
```

| Stored value | Routed to |
|---|---|
| `android` | FCM. There is no alternative; on Android, FCM *is* the transport. |
| `ios` | APNs directly when `PushConfig.apns` is set, otherwise FCM. |
| anything unrecognised, or `NULL` | FCM — **and only FCM**, so a setup without it cannot carry the row at all. |

Values are read case-insensitively, and `apple`, `iphone` and `ipad` are accepted as `ios` — this column is written by client code Zonai does not control, and `Platform.operatingSystem` says `ios` while plenty of apps store `iOS`. An unrecognised value is that row's problem and never the fan-out's: it falls back rather than failing everyone else's notification.

**Omitting `platformColumn` sends every recipient through FCM** — which is what an FCM-only app wants, and why the parameter is optional. It is *not* a general default, because that fallback only exists when FCM is configured.

### An APNs-only app must name the column

Configure `apns` and no FCM, omit `platformColumn`, and there is nothing to fall back to: every recipient arrives with no platform, FCM is the only route Zonai will pick without one, and it is not there.

Those recipients are counted as **transient failures** with a detail naming the missing configuration — never pruned, and retried by the next drain. So nothing is delivered and nothing is lost or cleared; it simply keeps not arriving until the column is named. The job's `transiently_failed` count equalling its recipient count, on a job that never fails, is what this looks like from the outside.

Transient rather than permanent on purpose: the tokens are valid and the *configuration* is wrong, and pruning there would clear every registration you have over a deployment mistake.

The same holds one platform at a time. An Android recipient with no FCM configured, or an iOS one with neither route configured, fails transiently for the same reason and with a detail naming what is missing.

## Put it on its own table

You *can* put the token column on `users`. Prefer not to, for two reasons:

- **A user has more than one device.** One column on `users` silently means one device per account — a phone and a tablet cannot both be registered.
- **Under `deleteRow`, a wiped phone would delete a user account.** Unrecoverable, and caused by a policy that reads as being about tokens.

Zonai cannot tell the two table shapes apart, which is exactly why the default pruning policy is the non-destructive one.

## Registering a token

Zonai does not register devices — your client app does, and then writes the token into this table like any other row, alongside the platform it belongs to. A typical shape is an upsert keyed on the device, so re-registering the same device updates its row instead of accumulating rows for a phone that keeps rotating its token.

Which SDK does the registering depends on the route:

| Route | On the device |
|---|---|
| FCM (Android, or iOS via FCM) | The Firebase Messaging SDK. The token is an FCM registration token. |
| APNs direct (iOS) | The OS, natively — `registerForRemoteNotifications`. **No Firebase SDK on the device at all.** The token is the raw APNs device token. |

The two are different strings for the same phone, which is the other reason the platform column is not optional guesswork: a token registered through one route is unknown to the other.

Rows with a `NULL` or empty token are skipped by every fan-out, so a pruned row costs nothing but the space it occupies.
