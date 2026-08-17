# Push notifications

Zonai sends push notifications through **Firebase Cloud Messaging**. You declare which column holds a device token; Zonai pages the recipient set, sends in batches, survives a restart mid-send, and clears tokens that FCM says are dead.

The design decisions behind all of this — and the ones deliberately deferred — are recorded in [push-design.md](push-design.md).

> **`await push(...)` does not mean the notification was delivered.** It means the job was written down. Nothing here, and nothing FCM offers, tells you a notification reached a phone. See [What the return value means](#what-the-return-value-means).

## Setup is not two lines, and nobody's is

FCM reaches iOS *through* APNs. "One integration covers both platforms" is true for **sending** and false for **setup**: you still upload an APNs authentication key to the Firebase console before an iPhone will receive anything. Budget for that.

What you need before any of the below works:

| | |
|---|---|
| A Firebase project | its **project ID**, not its display name |
| A service-account JSON key | Firebase console → Project settings → Service accounts → Generate new private key |
| An APNs auth key uploaded to Firebase | iOS only; Apple Developer → Keys → `.p8` |
| The FCM SDK in your client app | Zonai sends; the device has to be registered to receive |

## Step 1 — Declare the token column

A `deviceToken` column is how Zonai finds recipients. It is a semantic column type like `photo()` or `email()`, and declaring one is what makes the column nameable by `push` at all.

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

Two properties of this table are load-bearing:

- **The token column must be nullable.** The default prune writes `NULL` into it.
- **The table must have a primary key.** Zonai pages by it, and the cursor it saves is what lets a fan-out resume instead of restarting. A table without one is refused with a message saying so.

Everything else — the table's name, whether there is a `user_id`, what else lives on the row — is yours. Zonai reads exactly one column and writes exactly one column.

### Put it on its own table

You *can* put the token column on `users`. Prefer not to:

- A user has more than one device. One column on `users` silently means one device per account.
- Under `OnPermanentRejection.deleteRow`, a wiped phone would delete a user account.

The default (`clearColumn`) exists partly because nothing stops you doing this, and a destructive default cannot be justified when the framework cannot tell the two table shapes apart.

### Recording which platform a token belongs to

One row per device is the shape everything below assumes. A person with a phone and a tablet has two rows; replacing an app means a new token and, usually, a new row.

An FCM token and an APNs token are both opaque strings, and **nothing about the value says which service issued it.** Zonai will not guess from the shape — that works until an SDK changes its format, and then it fails silently, per device, in production. So the app records it:

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
```

Store `'ios'` or `'android'`. Case does not matter, and `apple`, `iphone` and `ipad` are accepted too — that column is written by client code Zonai does not control, and case is the first thing to vary.

Then name it when you send:

```dart no-analyze
await push(
  message,
  table: 'device_tokens',
  column: 'token',
  platformColumn: 'platform',
  where: In('user_id', recipientIds),
);
```

**It is optional, and omitting it is a complete setup.** A project with only FCM configured needs nothing here — every recipient goes to FCM, which is what happened before platforms existed. Naming the column is what unlocks sending to iOS without Firebase.

The reason it is opt-in rather than automatic: the fan-out reads **exactly the columns you name and nothing else**. That narrowness is what stops `push` from reading a table it was pointed at. Widening it by one column is a decision worth making on purpose.

A row whose platform is unrecognised — or null — goes to FCM, and a row that cannot be routed at all is reported as a transient failure rather than pruned. A misconfiguration must never cost a valid registration.

## Step 2 — Configure it

`AppConfig.push` is nullable, exactly like `AppConfig.email`. A project without it logs a warning and enqueues nothing.

```dart in:app-config
push: const PushConfig(
  projectId: 'my-firebase-project',
  credentials: PushCredentials.file('/etc/my-app/fcm-service-account.json'),
),
```

### Credentials: read the rotation cost before choosing

Every other Zonai secret arrives through `String.fromEnvironment` — a compile-time define baked into the worker executables. That is tolerable for an SMTP password. An FCM service account is an **asymmetric private key**, and it is not.

| Form | Rotation | Use it when |
|---|---|---|
| **`PushCredentials.file(path)`** | Replace the file, restart. | **Production.** The key never enters the binary. |
| `PushCredentials.inline(json)` | **Recompile and redeploy.** | Development, or a platform that only offers env injection. |

`.inline` is not wrong, but it means the key travels wherever the binary travels, and rotating it during an incident is a build. Choose it knowingly.

Never commit either form. `.file` points at a path your deploy places; `.inline` reads from `String.fromEnvironment`.

### The rest of `PushConfig`

| Field | Default | What it is |
|---|---|---|
| `onPermanentRejection` | `clearColumn` | What happens to a row whose token FCM rejects for good. See [Pruning](#pruning). |
| `batchSize` | 500 | Rows read, sent and committed per checkpoint. Also the crash blast radius — see [the guarantee](#the-guarantee-at-least-once). |
| `concurrency` | 8 | Sends in flight at once within a batch. |
| `maxAttemptsPerBatch` | 3 | Attempts a batch's *transient* failures get before the job pauses. |

**The defaults are starting points, not measured optima**, and the design record says so. `batchSize` in particular is three things at once — the memory bound, the checkpoint granularity, and how many duplicate notifications a crash can cause. Measure against your own recipient sizes before moving it.

## Step 3 — Send

```dart in:side-effects
final job = await push(
  PushMessage(
    title: 'New reply',
    body: 'Someone replied to your post',
    collapseKey: 'post:${after.id}',
    data: {'postId': '${after.id}'},
  ),
  table: 'device_tokens',
  column: 'token',
  where: In('user_id', recipientIds),
);

logger.info('queued push job ${job.value}');
```

You name a **set**, not a list. Zonai runs the query and pages it, so a hundred thousand recipients are never a hundred thousand tokens in memory — and the `where` can express a segment (`active = true and locale = 'en'`) without your code reading the rows and handing back tokens.

### Call it from `after*` hooks, never `before*`

A `before` hook runs prior to the write. A notification announcing something that then does not happen cannot be recalled. This is the first thing to get right and the easiest to get wrong.

Enqueuing *is* transactional — the job row is committed with your request. Sending is not: once the fan-out starts, nothing about the request can stop it. Throwing from an `after` hook fails the request after the write has committed, and a job already enqueued still runs.

### `PushMessage`

| Field | |
|---|---|
| `title`, `body` | What the person sees. |
| `collapseKey` | Replaces an earlier undelivered notification with the same key instead of stacking beside it. **Set this on anything sent from a fan-out** — see below. |
| `data` | `Map<String, String>`. FCM's data values are strings; the type says so rather than letting a number become `"1"` silently on the device. |

### Size

A notification is two short strings. A realistic one — a 27-character title, an 81-character body, a collapse key and three data ids — is **about 500 bytes on the wire**, against FCM's 4 KB limit.

`push` refuses a message that would not fit, at the call site, before a job exists. That check is not tidiness: FCM answers an over-limit payload with `INVALID_ARGUMENT`, which is *the same status it uses for a dead token*. Without the check, one oversized notification arrives at the fan-out looking exactly like every recipient unregistering at once — and would prune them all.

You will hit the screen long before you hit the limit. iOS shows roughly four lines and Android roughly two when collapsed; a body past a couple of hundred characters is truncated where nobody can read it. Put detail in `data` and let the app fetch the rest.

### What the return value means

`push` returns a `PushJobId` as soon as the job is **durably recorded**. That is a few milliseconds whether the set is ten recipients or a hundred thousand, which is what makes it safe to `await` inside a request-path hook.

It is **not**:

- a promise the notification was delivered — FCM offers no such receipt to anyone;
- awaitable to completion. There is no "wait for the fan-out" and there will not be one.

What you can do with the id is query `_push_jobs` for progress, per-outcome counts, and the reason a job failed. That collection is admin-gated like every other framework table, so read it with an admin identity (the admin UI, or a cron) rather than from a user request.

## What Zonai owns, and what stays yours

| Zonai | You |
|---|---|
| The `deviceToken` **column** — reads it, clears it | The table it lives on, its name, every other column |
| Paging, batching, checkpointing, backoff, retries | Which recipients a message is for (the `where`) |
| Classifying a rejection as permanent or transient | What a rejection *means*, via `onPushRejected` |
| `AppConfig.push`, credentials, the `_push_jobs` table | When to send, cooldowns, muting, quiet hours |

A framework that writes into your tables is a framework you have to trust. That trust is optional: see `OnPermanentRejection.none`.

## Pruning

When FCM says a token is dead — the app was uninstalled, or the registration rotated — Zonai tells you, then acts.

| `onPermanentRejection` | Effect |
|---|---|
| `clearColumn` | **Default.** Sets the token column to `NULL`. The row stays. |
| `deleteRow` | Deletes the row. Opt-in. |
| `none` | Zonai does nothing. `onPushRejected` is the only signal — and it still fires. |

**Only a permanent rejection prunes.** A timeout, a `503`, or a quota rejection is a transient failure: it is counted on the job row and retried within the batch, and it never touches the row. A token that timed out is not a token that is dead, and keeping those two apart is most of why this feature is in the framework rather than in your hook.

### What FCM actually returns

Verified against live FCM, not transcribed from its documentation:

| Sent | HTTP | `error.status` | Result |
|---|---|---|---|
| A well-formed token FCM never issued | 404 | `NOT_FOUND` | pruned |
| **A real app, uninstalled from a real device** | **404** | **`NOT_FOUND`** | **pruned** |
| A malformed token | 400 | `INVALID_ARGUMENT` | pruned |
| An iOS token whose app has no usable APNs credential | 401 | `UNAUTHENTICATED` + `THIRD_PARTY_AUTH_ERROR` | transient, **not** pruned |
| A key without FCM permission | 403 | `PERMISSION_DENIED` | job fails, **nothing pruned** |
| No credentials | 401 | `UNAUTHENTICATED` | job fails, **nothing pruned** |

`NOT_FOUND` is the one to notice, and the second row is why: an app was installed on a real device, issued a token, delivered to, then uninstalled — and the next send returned `NOT_FOUND`, not `UNREGISTERED`. Anything unrecognised is treated as *transient*, so handling only the documented spelling would leave dead tokens retried forever and pruned never. Both are handled, and both are tested.

### The hook

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

`onPushRejected` fires **before** the prune, so `row` is intact when you see it — under `clearColumn` the token has not been nulled yet, and under `deleteRow` the row still exists. It fires under all three settings, `none` included. A hook that throws is logged and does not stop the prune or the fan-out.

## The guarantee: at-least-once

**Duplicates are bounded by one batch. Exactly-once is not available.**

FCM exposes no idempotency key for `messages:send`, so a send that succeeds remotely and crashes before its outcome is committed will be retried. The batch size is therefore the blast radius of a crash.

Two things reduce what that costs you:

- **Collapse keys.** A duplicate carrying the same `collapseKey` *replaces* the earlier notification on the device instead of stacking beside it. This is the only mechanism that makes a duplicate invisible to the person holding the phone.
- **Checkpointing.** The cursor advances only after a batch's outcomes are committed, in the same transaction. A crash resumes at the last batch boundary rather than at the top.

### The other side of that trade, stated plainly

A **transient** failure inside a committed batch is not retried by a later pass. The batch's cursor has moved past it, and re-reading it would re-send to everyone else in the batch too. Those recipients are counted in `transiently_failed` on the job row, and they did not get the message.

So: retries happen *within* a batch (`maxAttemptsPerBatch`, with exponential backoff on `429`/`5xx`), not across passes. If `transiently_failed` is non-zero and matters to you, the job row is where you find out, and re-sending is your decision to make rather than one Zonai makes on your behalf.

## When sending actually happens

Enqueuing a job starts a drain immediately, so a notification does not wait for a timer. The `_drain_push_jobs` cron runs every minute as the **resume** path — for a job whose drain died mid-fan-out, or one enqueued by a process that has since restarted.

`_cleanup_push_jobs` runs nightly and purges *finished* jobs older than seven days. Running and pending jobs are never purged by age: a running job's row is its cursor, and deleting it would restart its fan-out from the top.

## Testing it without sending real notifications

FCM has no sandbox. Every endpoint Google publishes delivers to a real device, so there is no address you can point a staging deployment at and watch what happens. That leaves two honest options, and it is worth being clear about which one you are doing.

**A local stand-in.** `FcmPushCourier` takes a `baseUri`, and a service-account key file's `token_uri` decides where the OAuth2 exchange goes. Point both at a local server and the entire path runs unmodified — a real signed assertion, a real token exchange, real HTTP, real classification, real pruning. Zonai's own suite does exactly this: `apps/zonai/test/src/push/fake_fcm.dart` is an `HttpServer` implementing both endpoints, and it holds only the **public** half of a generated keypair, so it verifies the assertion the way Google does rather than rubber-stamping it.

`baseUri` is deliberately a constructor argument and **not** a `PushConfig` field. Config is parsed from yaml, and an endpoint override there would be a way to redirect production's notifications — access token and all — by editing a config file.

What this proves: that the request we build is one a correct FCM implementation accepts, and that an error body FCM documents produces the right outcome on the right row. What it cannot prove: **that Google behaves the way Google documents.** A stand-in written from the docs and code written from the same docs share any mistake in them silently. Do not read a green local run as "push is verified end to end".

**Checking your credentials on their own.** Before a device is involved at all, `apps/zonai/tool/fcm_probe.dart` asks Google directly whether a service-account key works:

```sh
dart run tool/fcm_probe.dart /etc/my-app/fcm-service-account.json
```

It sends to a token FCM has never issued, so nothing reaches a phone and nothing is pruned — the *error* is the diagnosis. A permanent rejection means the credentials are good and FCM got as far as judging the token. A `403 PERMISSION_DENIED` means the service account lacks the Firebase Cloud Messaging API Admin role, or the key belongs to a different project than you think. That last case is the common one and it is hard to see any other way: a Play/`androidpublisher` service account (Play billing, RevenueCat) is a real key, in a real Google project, that simply is not the FCM one.

**A real send.** The only thing that closes the gap above. You need a Firebase project, an app registered in it, and a service account with the **Firebase Cloud Messaging API Admin** role — note that an `androidpublisher` service account (the kind Play billing and RevenueCat use) is not that, and usually is not even in the same project. Then send to two devices: one with the app installed, one where it has been deliberately uninstalled. The uninstalled one must prune and the installed one must not. That single test is what validates the classification table this whole feature is built on.

For iOS, add an **APNs auth key** to the Firebase console first. It is a `.p8` from Certificates, Identifiers & Profiles → Keys with the APNs capability enabled — *not* an App Store Connect API key, which is also a `.p8`, also lives in `~/.appstoreconnect/private_keys/`, and cannot sign an APNs request. Without the right one, FCM cannot reach iOS at all.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `AppConfig.push is not configured` in the log, nothing sent | No `push:` in your `AppConfig` for this flavor. `push(...)` throws a `StateError` at the call site. |
| `"…" is a text column, not a deviceToken column` | The column is declared with `$.text(...)`. Change it to `$.deviceToken(...)`; Zonai will not read a column it was not pointed at. |
| `"…" has no primary key` | A fan-out cannot be checkpointed without one. |
| `PushMessage is N bytes, over the …-byte budget` | The notification is too large for FCM. Shorten the body; the screen truncates it long before this anyway. |
| `every recipient in a batch … INVALID_ARGUMENT` | Almost always a malformed message rather than N dead tokens. **Nothing was pruned** — the job failed instead. |
| `FCM rejected the credentials (403)` | The service account lacks the `firebase.messaging` scope, or the key is for a different project. The job fails; **no tokens are pruned** — a credentials mistake must not clear a table. |
| Android arrives, iOS does not | FCM has no usable APNs credential **for that app** — the key is missing, expired or revoked, *or* the bundle id is not a registered, push-enabled App ID. Either way it answers `401 UNAUTHENTICATED` with `errorCode: THIRD_PARTY_AUTH_ERROR` for those recipients only — counted as *transient*, never pruned, and the rest of the batch still delivers. Sending is one integration; setup is two. |
| `permanently_rejected` climbing steadily | Normal. It is the uninstall rate, and it is why pruning exists. |

## Not in v1

**Topics** are the right primitive for a true broadcast — one API call, no token list, no pruning, no restart-duplicate problem. When "notify everyone" comes up, the answer is topics rather than a bigger fan-out. Deferred because they bring their own surface (subscribe, unsubscribe, per-topic auth).

**Payload localization is decided against, not deferred.** Zonai does not translate notification text. Build the string before calling `push`: the app already knows its user's locale, and having the framework re-derive it would mean reading columns the fan-out deliberately does not select.

Also out of scope for now: APNs direct (`.p8`), web push, scheduled or delayed sends, delivery analytics, an in-app notification inbox, per-user preference storage, rich media, and badge counts.
