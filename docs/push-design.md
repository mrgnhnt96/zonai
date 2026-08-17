# Push notifications in Zonai core — design decisions

**Status:** **built.** v1 landed on `feat/push-notifications`; the user-facing guide is [push.md](push.md). See [What changed in the building](#16-what-changed-in-the-building) for where the code departs from the decisions below, and §15 for what the open questions turned out to be.
**Date:** 2026-08-15 (revised); implemented 2026-08-15
**Supersedes:** the design section of `i_lost_the_game/.agent-coordination/ZONAI_PUSH_HANDOFF.md`, which is correct about the goal and wrong about two mechanisms. See [Corrections to the brief](#13-corrections-to-the-brief).

This is a decision record, not a tutorial. `docs/push.md` gets written with the code.

> **Revision note.** The first draft of this document had `push(...)` take a list of tokens and return an awaited per-token result, so the *caller* could prune dead tokens. That is no longer the design. Recipients are now named by a **query over a recognized column**, and Zonai prunes. Sections 2, 3, 5 and 6 are the ones that changed; the reasoning for the change is in §3, because the old conflict did not get resolved differently — it stopped existing.

---

## 1. Do we build it at all?

**Yes.** In core, not as an optional package.

**Transaction-and-ordering semantics are framework work.** An app author sending FCM from an `afterCreateSuccess` hook has to get right: not minting an OAuth2 token per recipient, paging a recipient set without loading it all into memory, surviving a restart mid-fan-out, and distinguishing a token that is *dead* from one that *timed out*. Each of those is a thing frameworks exist to own, and most app-side implementations will get at least two of them wrong quietly.

**It is a real differentiator.** Supabase has no native push — it points you at OneSignal or Expo. Firebase has it because FCM is theirs. A self-hosted backend where notifications work out of the box is a concrete adoption argument, and one of the few remaining gaps in Zonai's surface.

**The shape already exists here, twice.** Email is server-side outbound delivery configured per flavor. And `photo()` is the closer precedent: a semantic column type that Zonai *recognizes across every user collection* and whose lifecycle Zonai *owns* — `_cleanup_unreferenced_photos` walks every `photo`/`photos` column found via `schemaShapes()` and deletes rows and files on its own schedule. Push tokens are that pattern applied to a different column type. We are not inventing an architecture, and auto-pruning is not a new kind of opinion for this framework to hold.

**Counterweight, on the record:** FCM reaches iOS *through* APNs, so "one integration covers both platforms" is true for **sending** and false for **setup** — the user still uploads an APNs auth key to the Firebase console. Push will not be a two-line feature for anyone, and `docs/push.md` must not imply otherwise.

---

## 2. How recipients are named

**Decision: a recognized column type, plus a `where` clause. Not a caller-supplied token list.**

A new `deviceToken` column type, alongside `photo` / `email` / `password` in `SchemaBuilder`, with a matching `ColumnShapeKind.deviceToken` so Zonai can find it through `schemaShapes()` exactly the way photo cleanup does:

```dart no-analyze
class DeviceTokenTable extends Table<DeviceToken> {
  DeviceTokenTable(super.$)
    : id = $.id('id', (s) => s.id),
      userId = $.text('user_id', (s) => s.userId),
      token = $.deviceToken('token', (s) => s.token);
}
```

Sending then names a *set*, not a list:

```dart no-analyze
final job = await push(
  message,
  table: 'device_tokens',
  where: In('user_id', recipientIds),
);
```

Three things follow from this, and they are the whole reason for the change:

1. **Zonai can page the recipient set** instead of the caller materialising it. A caller-supplied `List<String>` of a hundred thousand tokens is a hundred thousand tokens in memory before the first send.
2. **Zonai knows which column holds a token**, so it can prune one without being told where it lives. See §5.
3. **The query is expressible**, so segments (`where active = true and locale = 'en'`) do not require the app to write the query, read the rows, and hand back a list.

### The query is narrow by construction

The fan-out **projects only the primary key and the `deviceToken` column** — never any other column on the table. This is a security property, not an optimisation: `push` cannot be turned into a way to read columns the caller could not otherwise read, however the `where` is written.

**The token read is admin-gated and bypasses per-row rules.** Two gates, matching `mutate.purge`'s shape: the named column must be a `deviceToken` column, and the caller must be an admin identity (`CronJwt` qualifies). Per-row rule dispatch across a large recipient set is precisely the materialise-everything failure that made `_cleanup_logs` an OOM, and it is not worth re-creating for a query that can only ever return opaque tokens.

---

## 3. What `push(...)` returns, and the conflict that stopped existing

The brief asks for two things that cannot both be true as stated:

- `push(...)` as a **queued side effect** beside `get` / `mutate` / `email`
- `push(...)` **must report which tokens are dead**, so the caller can prune them

A queued side effect returns `void` *because* it is queued — `docs/cron.md` says so for `mutate`: *"a job cannot see how many rows it changed, or whether the write succeeded."* By the time the queue runs, the caller has returned.

**The first draft of this document resolved that by awaiting.** That was right given its premises and wrong given §2's. The caller only needed a result *because the caller had to prune*. Once Zonai recognises the token column, Zonai prunes, and the requirement evaporates rather than getting traded off. At a hundred thousand recipients nobody can await the answer anyway.

### Decision: `push(...)` enqueues a job and returns its id.

```dart no-analyze
Future<PushJobId> push(PushMessage message, {required String table, required Where where});
```

The returned future resolves as soon as the job is **durably recorded**, not when it completes. That is a few milliseconds regardless of whether the set is ten recipients or a hundred thousand, so it is safe to await inside a request-path hook.

**Why an id rather than `void`:** checkpointing (§4) requires an internal job table whether or not anyone reads it. Once that table exists, handing back its key costs nothing and gives the app progress, counts and failure reasons through an ordinary query — which is strictly better than the `void` the brief asked for and strictly better than the receipts table the first draft rejected as scope creep. The observability falls out of a mechanism we needed anyway.

**What it is not:** not a promise the notification was delivered, and not awaitable-to-completion. `docs/push.md` must say so where someone reaching for `await push(...)` will read it.

---

## 4. The fan-out job

**Decision: checkpointed, resumable, batched. At-least-once with a bounded duplicate window.**

A crashed fan-out that restarts from the beginning re-notifies everyone it already reached. For notifications this is the expensive failure: a miss is invisible, a duplicate is a support ticket. So the job persists its position.

**Keyset pagination, not `OFFSET`.** Each batch reads `WHERE <caller's where> AND pk > :cursor ORDER BY pk LIMIT :batchSize`. `OFFSET` degrades linearly and, worse, silently skips or repeats rows when the table is written to mid-scan — which it will be, because devices register while a fan-out is running.

**The cursor advances only after a batch's outcomes are recorded, in the same transaction.** A crash therefore resumes at the last committed batch boundary.

**Never materialise the recipient set.** This is not a hypothetical: `_cleanup_logs` SELECTed every row it was about to delete, materialised them, and dispatched a per-row rules check — an OOM on a small box, and the reason `mutate.purge` exists. The photo precedent this design otherwise follows *has the same bug* — `_cleanupUnreferencedPhotos` does `await db.select().from(photos)` with no limit and walks the result. **Follow the photo pattern's structure, not its implementation.** (That is now twice this design borrows a pattern and has to disown its implementation; see also `Courier` in §9.)

### The honest guarantee

**At-least-once, with duplicates bounded by one batch.** Exactly-once is not available: FCM exposes no idempotency key for `messages:send`, so a send that succeeds remotely and crashes before its outcome is committed will be retried. The batch size is therefore also the blast radius of a crash, and belongs in config.

Two mitigations, both documented rather than assumed:

- **Collapse keys.** `PushMessage` carries an optional collapse key (`collapseKey` on Android, `apns-collapse-id` on iOS). When set, a duplicate *replaces* the earlier notification on the device instead of stacking. This is the only mechanism that makes a duplicate invisible to the person holding the phone, and it is worth recommending by default for anything fired from a fan-out.
- **Bounded concurrency with backoff.** FCM has per-project quotas, and a large fan-out will meet them. A bounded worker pool with exponential backoff on `429`/`5xx`; the bound lives in `PushConfig`. Transient failure at scale is the normal case, not the exception.

---

## 5. Pruning

**Decision: Zonai prunes automatically. Both escape hatches exist — a config switch that decides whether Zonai acts, and a hook that fires either way so the app can observe.**

`PushConfig.onPermanentRejection`:

| Value | Effect |
| --- | --- |
| `clearColumn` | **Default.** Sets the `deviceToken` column to null. |
| `deleteRow` | Deletes the row. Opt-in. |
| `none` | Zonai does nothing; the hook is the only signal. |

**`clearColumn` is the default because the failure modes are not symmetric.** Nothing stops a developer putting the token column on their `users` table rather than a dedicated one. Under a `deleteRow` default, a wiped phone would delete a user account — unrecoverable, and caused by a setting nobody chose. Under `clearColumn` the worst case is a row with a null token, which is inert and cleanable. A destructive default has to be earned, and this one cannot be.

**The `onPushRejected` hook fires before the prune**, not after, so the row is still intact when the app sees it. It receives the row, the token, and the rejection reason. It fires under all three settings, including `none` — which is what makes `none` a usable choice rather than a silent one.

Only a **permanent** rejection (`UNREGISTERED`, `INVALID_ARGUMENT`) prunes. A transient failure never does; a token that timed out is not a token that is dead, and collapsing those two is exactly what this feature exists to get right.

---

## 6. Ownership boundary (revised)

The first draft drew this line as *"Zonai owns the transport, the app owns the tokens — Zonai will never read, write, or require a device-token table."* **That line has moved, and it moved deliberately rather than by drift.**

Zonai now reads from and writes to an app-owned table. What keeps that from becoming an opinion about the app's schema is that Zonai's knowledge is confined to **one column it was explicitly handed**:

| Zonai | The app |
| --- | --- |
| the `deviceToken` **column** — reads it, clears it | the table it lives on, its name, and every other column |
| paging, batching, checkpointing, backoff | which recipients a given message is for (the `where`) |
| classifying a rejection as permanent or transient | what a rejection *means* (via `onPushRejected`) |
| `AppConfig.push`, credentials, the internal jobs table | when to send, cooldowns, muting, quiet hours |

Zonai never requires a particular table name, never requires a `user_id`, and never reads a column it was not pointed at. The app declares one column; everything else stays the app's.

This is the same bargain `photo()` already makes, and it is worth naming that the bargain has a cost: a framework that deletes rows in your tables is a framework you have to trust. The config switch in §5 is what makes that trust optional.

---

## 7. API shape

### `PushMessage` — `libs/zonai_schema`

Title, body, an optional collapse key (§4), and a data payload of `Map<String, String>` — FCM's data values are strings, and typing it otherwise invites a silent `toString()`. The consuming app needs `lossEventId` and `causedById` there so a notification tap can deep-link and record the cascade chain. Serializable like `Email`, because it crosses the worker/host boundary.

### `PushJobId` and the jobs table

The job row carries: the message, the target table and serialized `where`, the cursor, per-outcome counts (delivered / permanently rejected / transiently failed), status, and timestamps. Queryable by the app through the id returned from `push`.

### Outcome classification

| Outcome | Meaning | Effect |
| --- | --- | --- |
| **delivered** | FCM accepted it | counted |
| **permanentlyRejected** | `UNREGISTERED`, `INVALID_ARGUMENT` — app uninstalled or registration rotated | hook fires, then prune per config |
| **transientlyFailed** | timeout, 5xx, `UNAVAILABLE`, quota | counted; retried within the job's backoff, never pruned |

Modelled as a **sealed type**, not an enum with a nullable reason, so a consumer handling two of three fails to compile rather than silently ignoring one.

---

## 8. Transport

**FCM HTTP v1 only.** Service-account JWT → OAuth2 access token → `POST /v1/projects/{projectId}/messages:send`.

**Token caching is required, not an optimisation.** One cached access token, refreshed on expiry, with single-flight so a concurrent batch mints one token rather than one per recipient.

---

## 9. `PushCourier` is an interface

This departs from the email precedent, where `Courier` is a concrete class calling `mailer.send` directly — and the departure is the point. Because email's transport is not injectable, `apps/zonai/test/src/email/courier_test.dart` can only assert the *missing-config warning*; there is no test of a successful send, a rejection, or a retry anywhere in the suite. Push must not inherit that gap, and it needs to test crash-resume, which is untestable against a real endpoint. It also leaves room for a `.p8` APNs implementation later without touching a call site.

---

## 10. Credentials

Zonai's config secrets arrive through `String.fromEnvironment` — **compile-time defines** baked into worker executables. Tolerable for an SMTP password. Materially worse for an FCM service account, which is an **asymmetric private key**: baking it into a distributed binary means rotation requires a recompile and redeploy, and the key travels anywhere the binary travels.

**Decision:** a sealed `PushCredentials` with two forms.

- **`.file(path)`** — read at runtime from disk. **Recommended for production.** Rotation is replace-the-file-and-restart; the key never enters the binary.
- **`.inline(json)`** — a JSON string from `String.fromEnvironment` like every other secret. Convenient for dev and for platforms that only offer env injection.

`docs/push.md` must state the recompile-to-rotate consequence of the inline form out loud, rather than leaving people to discover it during an incident.

`AppConfig.push` is nullable, exactly like `AppConfig.email`. A project with no push config logs a warning and enqueues nothing. A missing config must never throw; it must be *loud*.

---

## 11. Delivery semantics

- **Push is not transactional.** Not rolled back, not deduplicated. Neither is email today.
- **Call it from `after*` hooks, never `before*`.** A `before` hook runs prior to the write; a push announcing something that may not happen cannot be recalled. First screen of the docs, not a footnote.
- **Enqueuing is transactional; sending is not.** The job row is committed with the request. Once the fan-out starts, nothing about the request can stop it.
- **Throwing from an after hook fails the request after the write has committed.** A job already enqueued still runs.

---

## 12. Testing

Against a `FakePushCourier`, never the real FCM endpoint.

1. Access token cached and reused across a batch; refreshed once expired.
2. A permanent rejection surfaces as `permanentlyRejected` with its token.
3. A transient failure surfaces as `transientlyFailed`, *distinctly*, and does **not** prune.
4. `clearColumn` nulls the column; `deleteRow` deletes; `none` leaves the row untouched.
5. `onPushRejected` fires under all three settings, and fires **before** the row is modified.
6. **Crash-resume:** a job killed mid-fan-out resumes from its last committed cursor and does not restart from the top. This is the assertion the whole checkpointing design exists for; without it the feature is untested where it is hardest.
7. A recipient set larger than one batch pages through every row exactly once, with rows inserted mid-scan not causing skips.
8. A missing `AppConfig.push` logs a warning and enqueues nothing — asserted on captured log output, not "does not throw," which is the assertion that let the email version rot for twelve days.
9. `PushMessage` survives a JSON round trip. It crosses a worker boundary; a field that serializes in-process and not over IPC passes every unit test and fails in every real server.

No key material in a test fixture, a doc example, or a committed config.

---

## 13. Scope

### Planned next, not in v1

**Topics.** For a true broadcast, FCM topics are one API call with no token list, no pruning, and no restart-duplicate problem — strictly the right primitive for "everyone." Deferred because a project large enough to need it is not a project reaching for this feature first, and topics bring their own surface (subscribe / unsubscribe / per-topic auth) that would roughly double v1. Recorded here so it is a deferral rather than an omission: when broadcast comes up, the answer is topics, not a bigger fan-out.

### Out of scope for v1

APNs direct (`.p8`) · web push · scheduled or delayed sends · delivery analytics · an in-app notification inbox · per-user preference storage · rich media attachments · badge-count management.

### Decided against, rather than deferred

**Localization of payloads.** Recorded 2026-08-15, after it was raised as the natural next feature and rejected. The app builds the string; Zonai sends it.

The reasoning is not that it is hard, but that it is in the wrong place. Per-locale copy needs a locale on the recipient row and per-recipient rendering — and §2's projection deliberately reads only the primary key and the token, precisely so `push` cannot be turned into a way to read other columns. Localizing would mean widening that projection, trading the property that makes the feature safe for one the caller can already satisfy: an app knows its user's locale at the call site and can pass a finished `PushMessage`. Nothing is bought.

This also settles the adjacent question of email-style templates, which was asked and answered the same day: a notification is two short strings (~500 bytes on the wire against FCM's 4 KB, against ~6.8 KB for a single real email template), so there is no document to assemble, and the one use case that would justify a rendering engine — per-recipient personalization — is the same one the projection rules out. The `Email` subclass idiom (`SendOtpEmail` and friends) is the right precedent for reusable message shapes, and it costs nothing.

**v1 is: FCM, one checkpointed fan-out over a queried recipient set, with automatic pruning the developer can switch off.**

---

## 14. Corrections to the brief

| Claim | Verdict |
| --- | --- |
| Zonai has no existing push code | **Confirmed.** |
| `email/courier.dart` is the closest analog | **Partly.** Closest for *config and delivery*; `photo()` is closer for the part that turned out to matter — a recognized column type whose lifecycle Zonai owns. Follow email's structure, not its seams (§9). |
| Extension side effects (`get`/`mutate`/`email`) are queued and applied after the main transaction | **Refuted for `email`.** Only `mutate` is queued (`message_handler.dart:312, 326, 340`); on the host only `MutationRequest` is parked in `_pendingMutations`, while `SendEmailRequest` hits `courier.send` immediately and unawaited (`mailman.dart:820`). Email is not transaction-gated. This was the claim the "push must be a queued void side effect" design rested on. |

One further planning assumption:

> Zonai's live query streams already cover the foreground case completely … So the gap is precisely and only backgrounded devices.

**Does not currently hold.** As of `6a6f0d0`, the three `/db/stream*` routes deliver an initial frame but never push a frame for a mutation made after the stream opened. The foreground case does not work either, which makes push **more** load-bearing than the brief assumed.

---

## 15. Open questions — answered

1. **Batch size default: 500, and still unmeasured.** Shipped as a starting point chosen so that a crash duplicates a screenful rather than a mailing list. `docs/push.md` says out loud that it is not a measured optimum, which is the honest state — nobody has run a fan-out at a size where the three properties it controls pull against each other. **Still open as a measurement**, not as a decision.
2. **Concurrency default: 8, likewise unmeasured.** A bounded worker pool, the bound in `PushConfig`, exactly as sketched. The pool is written as N workers pulling from a shared index rather than `Future.wait` over chunks, so a slow send does not hold up the batch behind it.
3. **Who drains the queue: both, and that is the answer.** The cron alone was wrong. `_drain_push_jobs` runs every minute, but enqueuing also kicks a drain immediately — otherwise every notification waits up to a minute for a timer, which is not a notification service. The cron's real job is **resume**: a fan-out whose drain died mid-batch, or one enqueued by a process that has since restarted. The question's caution was well aimed and the answer is the reverse of what it expected: the cron is the fallback, not the mechanism.

   Passes are chained rather than skipped, so two callers arriving together serialize instead of one getting a misleading zero. Confirmed by running it, not by assuming: `push_fanout_test.dart` drives enqueue and drain against a real database.
4. **Retention: `_cleanup_push_jobs`, nightly, seven days, via `mutate.purge`.** Longer than `_cleanup_logs`' four days on purpose — the reason to read a job row is a complaint that a notification did or did not arrive, and those reach a developer days later rather than hours.

   One thing the question did not anticipate: the purge has to filter on **status**, not only age. A running job's row *is* its cursor, so purging one by age would restart its fan-out from the top and re-notify everyone it had already reached — retention silently causing the exact duplicate the checkpoint exists to prevent.

---

## 16. What changed in the building

Every decision above survived. These are the places the code says more than the design did, and one place it says something different.

**`push` takes a `column`, not just a `table`.** §2's example named only the table, which quietly assumed a table has one `deviceToken` column. Nothing enforces that, and picking "the first one found" would be a silent choice about which device a notification went to. The column is now named at the call site and validated against `schemaShapes()`.

**The recipient query is built host-side, not through the operations worker.** The operations layer's `list()` selects whole rows, and §2's projection is a security property rather than an optimisation — so the fan-out renders the caller's `Where` to SQL itself (`WhereX.sql`) and selects exactly two columns. The `where` is still parameterized; the identifiers are resolved through `schemaShapes()` before reaching a statement.

**The prune matches on the token as well as the key.** Not in the design, and a real gap: between reading a batch and committing it, a device can re-register and write a *new* token into the same row. Clearing by primary key alone would delete a live registration because a dead one used to be there.

**Counts resume from the job row.** The first implementation restarted them at zero on a resumed pass, so a job that sent 400 yesterday and 100 today reported 100. Found by the crash-resume test, which is the assertion §12 said the whole checkpointing design exists for — it earned its place immediately.

**The access-token refresh margin is applied at mint time, capped at half the lifetime.** Subtracting a five-minute margin from expiry at *read* time means a token with a shorter lifetime than the margin is never fresh, so every call mints a new one — the token endpoint hammered once per send, arrived at through the code that exists to prevent exactly that. Also found by a test.

**`PushTargetException` is a `SchemaException`.** `ZonaiDb._run` wraps anything it does not recognise in an opaque `StateError`, so a purpose-built exception type would have reached the author as "Failed to run database operation". Being part of the sealed hierarchy also forced the HTTP mapping to be chosen rather than defaulted (400).

**A transient failure inside a committed batch is not retried by a later pass.** This follows from batch-level checkpointing and was not stated. Retries happen *within* a batch; once the cursor moves past a batch, a recipient counted in `transiently_failed` did not get the message and will not be tried again. It is on the job row, and `docs/push.md` says so rather than leaving it to be discovered.

### Two things that had to be fixed to get here

**`raindrop.yaml` had been broken since `e4867b8`.** The 2026-08-15 raindrop sync made `driver` a required field, so `--migrate` threw before generating anything. It also needed `driver_import` and `schema_package_prefix` pointing at zonai_schema's *vendored* raindrop: the submodule's copy and the vendored one are two different `SqlDialect` types, and the generated snapshot entrypoint mixes them otherwise.

**`ZonaiDb` had no config seam.** `_run` rebinds `configResolverProvider` on every call, so a scope-level override is replaced before anything reads it — meaning any test touching `AppConfig` had to compile a config worker. Now injectable, `@visibleForTesting`.

---

## Related work this design turned up

**~~`_cleanupUnreferencedPhotos` materialises every photo row~~ — fixed before this was built.** The claim was true when written and was fixed in `2df7be7` ("page the photo-cleanup scans instead of reading both tables whole"), which landed on `main` first. Both scans are keyset-paged now.

Struck through rather than deleted, because the design leans on it twice: §4 says "follow the photo pattern's structure, not its implementation", and that instruction is now wrong in a way that matters — the current implementation *is* the pattern to follow, and the fan-out's paging is modelled on it directly.

**The `/db/stream*` claim in §14 was not re-checked.** It asserts that as of `6a6f0d0` the stream routes deliver an initial frame and never push another. Confirming or refuting it needs a running server, and nothing in push depends on the answer, so this implementation neither verified nor relied on it. Anyone quoting §14's conclusion — that push is *more* load-bearing than the brief assumed — should re-establish that first; it may have been fixed in the interval.
