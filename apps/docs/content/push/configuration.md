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
