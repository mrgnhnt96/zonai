---
title: Device Tokens
description: The deviceToken column type, and why the table it lives on is your decision rather than Zonai's.
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

## Put it on its own table

You *can* put the token column on `users`. Prefer not to, for two reasons:

- **A user has more than one device.** One column on `users` silently means one device per account — a phone and a tablet cannot both be registered.
- **Under `deleteRow`, a wiped phone would delete a user account.** Unrecoverable, and caused by a policy that reads as being about tokens.

Zonai cannot tell the two table shapes apart, which is exactly why the default pruning policy is the non-destructive one.

## Registering a token

Zonai does not register devices — your client app does, through the FCM SDK, and then writes the token into this table like any other row. A typical shape is an upsert keyed on the device, so re-registering the same device updates its row instead of accumulating rows for a phone that keeps rotating its token.

Rows with a `NULL` or empty token are skipped by every fan-out, so a pruned row costs nothing but the space it occupies.
