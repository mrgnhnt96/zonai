# Push notifications in Zonai core — design decisions

**Status:** decided, not built. Implementation starts after the next release.
**Date:** 2026-08-14
**Supersedes:** the design section of `i_lost_the_game/.agent-coordination/ZONAI_PUSH_HANDOFF.md`, which is correct about the goal and wrong about two mechanisms. See [Corrections to the handoff](#corrections-to-the-handoff).

This is a decision record, not a tutorial. `docs/push.md` gets written with the code.

---

## 1. Do we build it at all?

**Yes.** In core, not as an optional package.

Three reasons, in order of weight:

**Transaction-and-ordering semantics are framework work.** An app author sending FCM from an `afterCreateSuccess` hook has to get right: not sending for a write that did not land, not minting an OAuth2 token per recipient, and distinguishing a token that is dead from a token that timed out. Each of those is a thing frameworks exist to own. Most app-side implementations will get the third one wrong silently, and pay for it forever in wasted API calls.

**It is a real differentiator.** Supabase has no native push — it points you at OneSignal or Expo. Firebase has it because FCM is theirs. A self-hosted backend where notifications work out of the box is a concrete adoption argument, and one of the few remaining gaps in Zonai's surface.

**The shape already exists here.** Email is server-side outbound delivery, configured per flavor, invoked from extensions and crons, with a payload type in `zonai_schema` and a courier behind a scoped provider. Push is the same shape. We are not inventing an architecture.

**Honest counterweight, so it is on the record:** FCM reaches iOS *through* APNs, which means "one integration covers both platforms" is true for **sending** and false for **setup** — the user still uploads an APNs auth key to the Firebase console and configures an iOS app there. Push will not be a two-line feature for anyone, and `docs/push.md` must not imply otherwise.

---

## 2. The central conflict, and how it resolves

The handoff asks for two things that cannot both be true as stated:

- `push(...)` as a **fourth queued side effect** beside `get` / `mutate` / `email`
- `push(...)` **must report which tokens are dead**, so the caller can prune them

A queued side effect returns `void` precisely *because* it is queued — `docs/cron.md` says so for `mutate.create` / `update` / `delete`: *"a job cannot see how many rows it changed, or whether the write succeeded."* A queued call has nobody to hand a result back to; the caller returned long ago.

### Decision: `push(...)` is awaited and returns `Future<PushResult>`.

Not a void queued side effect. The reasoning, in the order that settled it:

**a. The premise that forces queuing is false.** The handoff argues push must be queued because "a push for a row whose transaction later rolls back must never go out," and that email already works this way. Email does not work this way. On the worker, `_emailProvider` calls `sendRequest(SendEmailRequest(...))` with **no** `queueSideEffect` wrapper — only the three `mutate` calls have one (`message_handler.dart:312, 326, 340`). On the host, only `MutationRequest` is parked in `_pendingMutations`; `SendEmailRequest` hits `courier.send(request.email)` immediately and unawaited (`mailman.dart:820`). Email is fire-and-forget and is **not** transaction-gated today. Copying email exactly would have produced exactly the bug the handoff was trying to avoid — and unlike an email, a push cannot be followed by a correction.

**b. Where it is actually called, there is nothing left to gate on.** The consumer calls push from `afterCreateSuccess`. `docs/extensions.md:50` and `:131`: after hooks run **after the database change has already committed**. The row is in the database before the hook body starts. Queuing would defer a send past a commit that already happened.

**c. The result is the entire point.** Dead-token pruning is the one design decision the handoff flags as easy to get wrong, and it is unavailable in every void-returning design. Building the void version and bolting a result channel on later means inventing a second mechanism — a receipts table or a registered callback — to carry information a return value already carries.

**d. Awaiting is what makes it testable.** A fan-out that reports nothing can only be asserted through a spy on the transport. A fan-out that returns a result can be asserted on its own terms.

### The cost of this decision, stated plainly

**An awaited fan-out adds its full latency to the HTTP response.** FCM HTTP v1 has no true multicast — the legacy batch endpoint is deprecated, and the Admin SDK's `sendEach`/`sendMulticast` are client-side loops. A 200-recipient fan-out is 200 HTTP requests. Awaiting that inside a request-path hook is not acceptable.

So the caller decides:

- **Await it** when the recipient count is small and bounded, or when you are in a cron and nobody is waiting on a response.
- **Do not await it** when it is a large fan-out on a request path. You forfeit the result, which means you forfeit pruning for that batch.
- **Best of both:** enqueue the recipients from the hook and fan out from a cron, awaiting there. This is the pattern `docs/push.md` will recommend for anything unbounded.

**Why losing a result batch is survivable:** a permanent rejection is a property of the token, not of the attempt. `UNREGISTERED` does not become valid again. So a dropped result costs one wasted API call on the next fan-out, which will report it again. Pruning is an optimisation with a repeating signal, not a correctness requirement with one chance. This is what makes the "do not await" escape hatch safe to offer rather than a trap.

---

## 3. Ownership boundary

**Zonai owns the transport. The app owns the tokens.**

Zonai will never read, write, or require a device-token table. It does not know what your tokens table is called, what else is on the row, or which user a token belongs to. It takes tokens as arguments and reports outcomes per token.

| Zonai | The app |
| --- | --- |
| `push(...)`, `PushMessage`, `PushResult` | the `device_tokens` table and its schema |
| FCM HTTP v1 courier, OAuth2 token cache | which users receive a given notification |
| per-token delivered / rejected / failed | acting on a permanent rejection (deleting the row) |
| `AppConfig.push` and credential loading | cooldowns, muting, quiet hours, preferences |

This is the boundary that keeps push a capability rather than an opinion. The moment Zonai owns a tokens table it owns a migration, a rules surface, and a schema every consumer has to bend to.

---

## 4. API shape

### `PushMessage` — `libs/zonai_schema`

Carries a title, a body, and a **data payload** of `Map<String, String>` (FCM's data values are strings; typing it otherwise invites a silent `toString()`). The consuming app needs `lossEventId` and `causedById` in there so a notification tap can deep-link and record the cascade chain.

Serializable to/from JSON like `Email`, because it crosses the worker/host boundary.

### `push(...)` — a fourth verb beside `get` / `mutate` / `email`

Takes a `PushMessage` and the target tokens. Returns `Future<PushResult>`.

### `PushResult`

A list of per-token outcomes, each one of three states:

| Outcome | Meaning | What the caller should do |
| --- | --- | --- |
| **delivered** | FCM accepted it | nothing |
| **permanentlyRejected** | `UNREGISTERED`, `INVALID_ARGUMENT` — the app was uninstalled or the registration rotated | delete the token row |
| **transientlyFailed** | timeout, 5xx, `UNAVAILABLE`, quota | keep it; it may work next time |

Each outcome carries the token it refers to and a reason string. The three-way split is deliberate: a boolean cannot express "keep this and retry" versus "this will never work again," and collapsing them is what makes token tables grow forever.

**Sealed, not an enum with a nullable reason** — so a caller handling only two of the three states fails to compile rather than silently ignoring one.

---

## 5. Transport

**FCM HTTP v1 only.** Service-account JWT → OAuth2 access token → `POST https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`.

**`PushCourier` is an interface.** This departs from the email precedent, where `Courier` is a concrete class calling `mailer.send` directly — and the departure is the point. Because email's transport is not injectable, `apps/zonai/test/src/email/courier_test.dart` can only assert the *missing-config warning*; there is no test of a successful send, a rejection, or a retry anywhere in the suite. Push must not inherit that gap, and an interface is what prevents it. It also leaves room for a `.p8` APNs implementation later without touching a call site.

**Token caching is required, not an optimisation.** One cached access token, refreshed on expiry, with single-flight so a concurrent fan-out to 200 recipients mints one token rather than 200. Mint-per-send would be both slow and a good way to get rate-limited by Google.

---

## 6. Credentials

This is the decision with the sharpest security edge, and the existing pattern does not fit cleanly.

Zonai's config secrets arrive through `String.fromEnvironment` — **compile-time defines** baked into worker executables at `dart compile exe` time (`docs/config-and-env-flavors.md`). That is tolerable for an SMTP password. It is materially worse for an FCM service account, which is an **asymmetric private key**: baking it into a distributed binary means rotation requires a recompile and redeploy, and the key travels anywhere the binary travels.

**Decision:** `PushConfig` accepts credentials two ways, via a sealed `PushCredentials`:

- **`PushCredentials.file(path)`** — read at runtime from disk. **Recommended for production.** Rotation is replace-the-file-and-restart. The key never enters the binary.
- **`PushCredentials.inline(json)`** — a JSON string, which can come from `String.fromEnvironment` like every other secret. Convenient for dev and for platforms that only offer env injection.

`docs/push.md` must state the recompile-to-rotate consequence of the inline form out loud rather than leaving people to discover it during an incident.

`AppConfig.push` is nullable, exactly like `AppConfig.email`. A project with no push config logs a warning and skips the send — matching email's behaviour, which `known-issues.md #10` and the courier test already pin. A missing config must never throw; it must be loud.

---

## 7. Delivery semantics, written down because they will be assumed otherwise

- **Push is not transactional.** It is not rolled back, retried, or deduplicated by Zonai. Neither is email today.
- **Call it from `after*` hooks, never from `before*` hooks.** A `before` hook runs prior to the write; a push sent there announces something that may not happen, and cannot be recalled. `docs/push.md` says this in the first screen, not in a footnote.
- **Throwing from an after hook fails the request after the write has committed** (`docs/extensions.md:50`). A push that already went out stays out. Do not treat a failed request as a signal that no notification was sent.
- **No automatic retry in v1.** A transient failure is reported and the caller decides. A retry queue that nobody asked for is a durability promise we would then have to keep.

---

## 8. Testing

Against a `FakePushCourier`, never the real FCM endpoint. Minimum coverage, and it is deliberately stricter than email's:

1. Access token is cached and reused across sends in one fan-out.
2. Access token is refreshed once it expires.
3. A permanent rejection surfaces as `permanentlyRejected` with the token attached.
4. A transient failure surfaces as `transientlyFailed`, distinctly.
5. A multi-token fan-out returns one outcome per token, in the same order, including when the outcomes differ.
6. A missing `AppConfig.push` logs a warning and sends nothing — asserted on captured log output, not on "does not throw," which is the assertion that let the email version rot for twelve days.
7. `PushMessage` survives a JSON round trip. It crosses a worker boundary; a field that serializes in-process and not over IPC passes every unit test and fails in every real server.

No key material in a test fixture, a doc example, or a committed config.

---

## 9. Explicitly out of scope for v1

Named so that "should we also…" has an answer that is not a discussion:

APNs direct (`.p8`), web push, topics and topic subscription management, a retry queue, scheduled or delayed sends, delivery analytics, an in-app notification inbox, per-user preference storage, localization of payloads, rich media attachments, badge-count management.

v1 is: FCM, sent once, with an honest result.

---

## 10. Corrections to the handoff

`ZONAI_PUSH_HANDOFF.md` asks for three things to be confirmed or refuted. Results:

| Claim | Verdict |
| --- | --- |
| Zonai has no existing push code | **Confirmed.** |
| `apps/zonai/lib/src/email/courier.dart` is the closest analog | **Confirmed** as a shape. Not as an implementation — its transport is not injectable, and its test coverage is one warning. Follow the structure, not the seams. |
| Extension side effects (`get`/`mutate`/`email`) are queued and applied after the main transaction | **Refuted for `email`.** Only `mutate` is queued (`message_handler.dart:312, 326, 340`; `mailman.dart:820`). Email fires immediately and is not transaction-gated. This is the claim the whole "push must be a queued void side effect" design rested on. |

One more thing the handoff's planning assumed that is no longer true:

> Zonai's live query streams (`client.db.listen`) already cover the foreground case completely … So the gap is precisely and only backgrounded devices.

**That premise does not currently hold.** As of `6a6f0d0`, the three `/db/stream*` routes deliver an initial frame but never push a frame for a mutation made after the stream opened — they are a one-shot GET wearing a stream's clothes. The foreground case does not work either. This makes push **more** load-bearing than the handoff assumed, not less, and it means push should not be deferred on the strength of streaming working.

---

## 11. Open questions

Not blockers; decide during implementation.

1. **Does `push` go through rules?** `email` does not. A push is not a row operation and has no row to authorize, so the default answer is no — but a `canPush`-style hook may be wanted later for muting. Do not build it in v1; do not design it out.
2. **Fan-out concurrency.** 200 sequential HTTP calls is slow; 200 concurrent ones may trip FCM quota. A bounded pool is probably right, and the bound probably belongs in `PushConfig`. Measure before picking a number.
3. **Should `push` be reachable from a cron?** It falls out of the side-effect wiring for free, and `docs/push.md`'s recommended pattern for large fan-outs depends on it. Confirm it works rather than assuming it does — the cron `get` defect (`1d95261`) was exactly a side effect that existed everywhere except where it was needed.
