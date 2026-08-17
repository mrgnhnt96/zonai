---
title: Push Configuration
description: PushConfig, the two credential forms and their very different rotation costs, and the batching defaults.
---

`AppConfig.push` is nullable, exactly like `AppConfig.email`. A project without it logs a warning and enqueues nothing — a missing config is loud, never fatal.

```dart in:app-config
push: const PushConfig(
  projectId: 'my-firebase-project',
  credentials: PushCredentials.file('/etc/my-app/fcm-service-account.json'),
),
```

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
| `onPermanentRejection` | `clearColumn` | What happens to a row whose token FCM rejects for good. See [Dead Tokens](/push/dead-tokens). |
| `batchSize` | 500 | Rows read, sent and committed per checkpoint. |
| `concurrency` | 8 | Sends in flight at once within a batch. |
| `maxAttemptsPerBatch` | 3 | Attempts a batch's *transient* failures get before the job pauses. |

**These defaults are starting points, not measured optima.** Saying so is more useful than a number presented with false confidence.

`batchSize` in particular is three things at once:

1. the **memory bound** — how many rows are held at a time;
2. the **checkpoint granularity** — how much work a crash costs;
3. the **crash blast radius** — how many duplicate notifications a crash can cause, since the fan-out is at-least-once.

Raising it makes a large fan-out faster and a crash more expensive, in exactly that proportion. Measure against your own recipient sizes before moving it.

`concurrency` bounds how hard a single batch hits FCM. Sequential is slow; unbounded meets FCM's per-project quota, which is a `429` rather than an error you asked for. The transport backs off exponentially on `429` and `5xx`.

## Per flavor

`AppConfig` is resolved per flavor, so a staging build can point at a different Firebase project — or at none, in which case staging enqueues nothing and says so in the log rather than sending production notifications from a test run.

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
- **A sandbox.** `useSandbox: true` sends to `api.sandbox.push.apple.com`, which FCM has no equivalent of. Development-build tokens live only there, and production tokens only in production; the symptom of mixing them is `BadDeviceToken` on a token that is perfectly valid.

### `bundleId` is not cosmetic

It becomes the `apns-topic` header, and one key can serve every app on a team, so it is the only thing saying which app a notification is for. Get it wrong and Apple answers `DeviceTokenNotForTopic` for **every** recipient at once. Zonai treats that as a transient failure naming the config field, precisely because a uniform config fault must never be read as every device being dead.

## Two `.p8` files that are not interchangeable

For iOS, FCM needs an **APNs auth key** uploaded to the Firebase console. It is a `.p8` created under *Certificates, Identifiers & Profiles → Keys* with the Apple Push Notifications service capability enabled.

Uploading it is a **console-only** step. The Firebase Management API has no APNs endpoints at all — the only APNs references in Google's API surface are `ApnsConfig`, which is per-message send options, not credentials. So this one part of setup cannot be scripted, cannot be put in Terraform, and cannot be done by CI: someone opens Project settings → Cloud Messaging and uploads the file, along with its **Key ID** and your **Team ID**.

Which makes the next point sharper than it looks. An **App Store Connect API key** is also a `.p8`, is also downloaded from Apple, and conventionally lives in `~/.appstoreconnect/private_keys/AuthKey_XXXXXXXX.p8` — the same filename shape. It cannot sign an APNs request and cannot be uploaded as an APNs key. Having one is not having the other, and the resulting failure is silent in the direction that matters: Android keeps arriving, iOS never does.

A `.p8` also carries **no key ID inside it** — the file is an unadorned PKCS#8 private key, byte-indistinguishable from any other. The filename is the only record of which key it is, so a renamed or re-downloaded file can leave you entering a Key ID that belongs to a different key entirely. The console accepts the pair without complaint and iOS delivery simply never works.

