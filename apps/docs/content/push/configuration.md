---
title: Push Configuration
description: PushConfig, the credential forms and their very different rotation costs, the batching defaults, and the APNs and Web Push halves.
---

`AppConfig.push` is nullable, just like `AppConfig.email`. If it is not set, the server logs `Cannot send a push notification because AppConfig.push is not configured. Nothing was enqueued.`, and the `push(...)` call throws a `StateError` in your hook or cron, where the stack trace points at the code that tried to send. The server keeps running either way.

`PushConfig` carries **three independent halves**: FCM, APNs and Web Push. At least one is required and none is privileged. An Android app configures FCM. An iOS-only app configures APNs and no Firebase project at all. A web app configures Web Push. An app on more than one platform configures each half it needs and names a [platform column](/push/device-tokens#the-platform-column) so each recipient is routed.

```dart in:app-config
push: const PushConfig(
  projectId: 'my-firebase-project',
  credentials: PushCredentials.file('/etc/my-app/fcm-service-account.json'),
),
```

Two fields, both FCM's. Partially configuring one half is refused by `AppConfig.validate` rather than read as "that transport is off" — a project id with no key would otherwise silently drop every Android recipient.

## Credentials: read the rotation cost before choosing

Every other Zonai secret arrives through `String.fromEnvironment` — a compile-time define baked into the worker executables. That is tolerable for an SMTP password. An FCM service account is an **asymmetric private key**, and it is not.

| Form | Rotation | Use it when |
|---|---|---|
| **`PushCredentials.file(path)`** | Replace the file, restart. | **Production.** The key never enters the binary. |
| `PushCredentials.inline(json)` | **Recompile and redeploy.** | Development, or a platform that only offers env injection. |

`.inline` is not wrong, but it means the key travels wherever the binary travels, and rotating it during an incident is a build rather than a file copy. Choose it knowingly.

Never commit either form. `.file` points at a path your deploy places; `.inline` reads from `String.fromEnvironment`.

## The rest of `PushConfig`

| Field | Default | What it is |
|---|---|---|
| `onPermanentRejection` | `clearColumn` | What happens to a row whose token a transport rejects for good. See [Dead Tokens](/push/dead-tokens). |
| `batchSize` | 500 | Rows read, sent and committed per checkpoint. This is also the crash blast radius (see [Delivery Guarantees](/push/delivery-guarantees)). |
| `concurrency` | 8 | Sends in flight at once within a batch. |
| `maxAttemptsPerBatch` | 3 | Attempts a batch's *transient* failures get before the job pauses. |

**These defaults are starting points, not measured optima.** Saying so is more useful than a number presented with false confidence.

`batchSize` in particular is three things at once:

1. the **memory bound** — how many rows are held at a time;
2. the **checkpoint granularity** — how much work a crash costs;
3. the **crash blast radius** — how many duplicate notifications a crash can cause, since the fan-out is at-least-once.

Raising it makes a large fan-out faster and a crash more expensive, in exactly that proportion. Measure against your own recipient sizes before moving it.

`concurrency` bounds how hard a single batch hits the transport, and it applies to every transport: sequential is slow, while unbounded meets FCM's per-project quota, APNs' documented per-connection limits or a Web Push service's rate limit — a `429` rather than an error you asked for. Every transport backs off exponentially on `429` and `5xx`. The shape underneath differs — FCM and Web Push are bounded pools of independent POSTs, APNs multiplexes one HTTP/2 connection — but the knob is the same one.

## Per flavor

`AppConfig` is resolved per flavor, so a staging build can point at a different Firebase project, a sandbox APNs host, or at nothing — in which case `push(...)` throws in staging and the log says why. You never accidentally send production notifications from a test run.

## Reaching iOS without Firebase

FCM delivers to iOS by proxying to APNs with a key you upload to its console. Zonai can skip that and talk to Apple directly:

```dart no-analyze
push: PushConfig(
  // Android still goes through FCM — on Android, FCM *is* the transport.
  projectId: 'my-firebase-project',
  credentials: PushCredentials.file('/etc/my-app/fcm-service-account.json'),

  // iOS goes straight to Apple.
  apns: ApnsConfig(
    credentials: ApnsCredentials.file('/etc/my-app/AuthKey_ABCD123456.p8'),
    keyId: 'ABCD123456',
    teamId: 'U2G2XV3688',
    bundleId: 'com.example.myapp',
  ),
),
```

Both halves are optional and at least one is required. An iOS-only app omits `projectId` and `credentials` entirely and needs **no Firebase project at all**. Setting one FCM field without the other is refused rather than treated as "FCM is off", because that would silently drop every Android recipient.

Recipients are routed by the `platform` column — see [Device Tokens](/push/device-tokens), which also covers what happens to a recipient no configured transport can carry.

Switching iOS between the two routes is a config change on the server and a **re-registration on the device**. Your schema does not change — same token column, same platform column — but the token value comes from whichever SDK registered the phone, and an FCM registration token is not an APNs device token. Ship the client change, let devices write their new tokens on next launch, and the two halves meet without a migration.

### What direct APNs buys

- **No console step.** The APNs key upload below has no API; going direct removes it.
- **One less failure mode.** `THIRD_PARTY_AUTH_ERROR` — FCM's answer when its APNs key lapses — cannot happen when there is no proxy.
- **A sandbox.** `useSandbox: true` sends to `api.sandbox.push.apple.com`, which FCM has no equivalent of. Development-build tokens live only there, and production tokens only in production; the symptom of mixing them is `BadDeviceToken` on a token that is perfectly valid. `useSandbox` is only the default for rows stored as `ios`: a row stored as `ios-sandbox` always goes to the sandbox, so one server can serve development and production builds at once — see [Development builds and TestFlight on one server](/push/device-tokens#development-builds-and-testflight-on-one-server).

### `bundleId` is not cosmetic

It becomes the `apns-topic` header, and one key can serve every app on a team, so it is the only thing saying which app a notification is for. Get it wrong and Apple answers `DeviceTokenNotForTopic` for **every** recipient at once. Zonai treats that as a transient failure naming the config field, precisely because a uniform config fault must never be read as every device being dead.

## Reaching browsers with Web Push

Browsers and installed PWAs are reached with standard Web Push: RFC 8030 delivery, RFC 8291 payload encryption and RFC 8292 VAPID. Each browser ships its own push service (Google's for Chrome and Edge, Mozilla's for Firefox, Apple's for Safari), and they all accept the same signed, encrypted request. There is no Firebase project, no Apple account and no console step.

```dart no-analyze
push: PushConfig(
  webPush: WebPushConfig(
    // The same string the app passes as applicationServerKey.
    publicKey: 'BO_dZrvdyPvN…',
    privateKey: WebPushPrivateKey.file('/etc/my-app/vapid.pem'),
    subject: 'mailto:ops@example.com',
  ),
),
```

`webPush` is a third half beside FCM and APNs. It is optional, and it can be the only one configured: a web-only app needs nothing else. Recipients reach it by storing `web` in the [platform column](/push/device-tokens#the-platform-column). A `web` row with no `webPush` configured is never sent through FCM. It is counted as a transient failure that names the missing config, and it is never pruned.

| Field | What it is |
|---|---|
| `publicKey` | The P-256 public key as a base64url uncompressed point (65 bytes, starting `0x04`). Browsers bind each subscription to it, and it is sent as the `k=` half of every `Authorization: vapid` header. |
| `privateKey` | `WebPushPrivateKey.file(path)` or `.inline(key)`, with the same rotation trade as the FCM credentials above. Either holds a PEM key (PKCS#8 or SEC1) or the bare base64url 32-byte scalar most VAPID tools print. |
| `subject` | A `mailto:` address or an `https:` URL: who a push service should contact about this server's traffic. It becomes the JWT's `sub`, and Apple's push service refuses a send without one. |

`AppConfig.validate` refuses a half-configured `webPush`: a public key that is not a 65-byte point, an empty or unreadable inline private key, or a subject that is neither `mailto:` nor `https:`. At the first send, Zonai also checks that the private key derives the public key. A mismatched pair fails the job instead of being sent, because every push service would answer `403` to it.

### Generating the key pair

Generate it once, locally:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out vapid.pem
openssl ec -in vapid.pem -pubout -outform DER | tail -c 65 | base64 | tr '/+' '_-' | tr -d '='
```

The first command writes the private key, ready for `WebPushPrivateKey.file`. The second prints `publicKey`. `npx web-push generate-vapid-keys` works too, and its base64url private key goes in `WebPushPrivateKey.inline`. Keep the private key out of the repository, like every other key on this page.

**Rotating the pair orphans every subscription.** A browser binds its subscription to the public key it subscribed with, so after a rotation each push service answers `403` until the app calls `subscribe` again with the new key. Zonai counts those as transient and never prunes them, because the subscription is still valid for the old key. Plan a rotation as a client release, not only a server change.

### On the client

The token is the browser's whole subscription, stored as the JSON string `PushSubscription.toJSON()` returns:

```js
const registration = await navigator.serviceWorker.register('/sw.js');
const subscription = await registration.pushManager.subscribe({
  userVisibleOnly: true,
  applicationServerKey: VAPID_PUBLIC_KEY, // WebPushConfig.publicKey
});
// Write this string to the deviceToken column, with platform 'web'.
const token = JSON.stringify(subscription);
```

```json
{"endpoint":"https://fcm.googleapis.com/fcm/send/…","expirationTime":null,"keys":{"p256dh":"BCVx…","auth":"BTBZ…"}}
```

A value that does not parse as a subscription is that row's problem and never the fan-out's. The same applies to an endpoint that is not `https`, which Zonai refuses so that a row can never point the server at an internal address. That row counts as a transient failure, and everyone else's notification goes out.

The service worker receives the payload as JSON with `title`, `body`, `tag` and `data`. `tag` is the message's `collapseKey`, and it is what `showNotification` replaces on:

```js
// sw.js
self.addEventListener('push', (event) => {
  const { title, body, tag, data } = event.data.json();
  event.waitUntil(self.registration.showNotification(title, { body, tag, data }));
});
```

On iPhone and iPad, Web Push works only for a site added to the home screen (iOS 16.4 and later). In Safari's browser tab, `pushManager` is not offered at all.

### What is sent

Each recipient gets its own `POST` to its subscription's endpoint, through the same bounded pool as FCM. The body is one `aes128gcm` record, encrypted to that browser's keys. The headers are:

| Header | Value |
|---|---|
| `Authorization` | `vapid t=<JWT>, k=<publicKey>`. The ES256 JWT's `aud` is the endpoint's origin and it expires in 12 hours, inside RFC 8292's 24-hour cap. One JWT is reused for every subscription on the same push service. |
| `Content-Encoding` | `aes128gcm` |
| `TTL` | `86400`. A push service holds the message for a browser that is offline for up to a day. |
| `Urgency` | `high` |
| `Topic` | The `collapseKey` when it is at most 32 base64url characters, otherwise a 32-character hash of it, so that the same key always gives the same topic. Omitted when there is no collapse key. |

One record carries at most 3993 bytes of payload. The enqueue-time size check described in [Sending](/push/sending#size-is-checked-at-enqueue-not-at-send) keeps every message under that limit.

## Two `.p8` files that are not interchangeable

For iOS, FCM needs an **APNs auth key** uploaded to the Firebase console. It is a `.p8` created under *Certificates, Identifiers & Profiles → Keys* with the Apple Push Notifications service capability enabled.

Uploading it is a **console-only** step. The Firebase Management API has no APNs endpoints at all — the only APNs references in Google's API surface are `ApnsConfig`, which is per-message send options, not credentials. So this one part of setup cannot be scripted, cannot be put in Terraform, and cannot be done by CI: someone opens Project settings → Cloud Messaging and uploads the file, along with its **Key ID** and your **Team ID**.

Which makes the next point sharper than it looks. An **App Store Connect API key** is also a `.p8`, is also downloaded from Apple, and conventionally lives in `~/.appstoreconnect/private_keys/AuthKey_XXXXXXXX.p8` — the same filename shape. It cannot sign an APNs request and cannot be uploaded as an APNs key. Having one is not having the other, and the resulting failure is silent in the direction that matters: Android keeps arriving, iOS never does.

A `.p8` also carries **no key ID inside it** — the file is an unadorned PKCS#8 private key, byte-indistinguishable from any other. The filename is the only record of which key it is, so a renamed or re-downloaded file can leave you entering a Key ID that belongs to a different key entirely. The console accepts the pair without complaint and iOS delivery simply never works.

