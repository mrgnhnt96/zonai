---
title: Push Notifications
description: Send through Firebase Cloud Messaging or straight to APNs, with a checkpointed fan-out Zonai owns end to end.
---

Zonai sends push notifications through **Firebase Cloud Messaging**, or **straight to APNs** for iOS with no Firebase in the path. You declare which column holds a device token; Zonai pages the recipient set, sends in batches, survives a restart mid-send, and clears tokens the transport reports as dead.

Supabase has no native push — it points you at OneSignal or Expo. Firebase has it because FCM is theirs. A self-hosted backend where notifications work out of the box is one of the few gaps left in Zonai's surface, and this closes it.

## Two routes to a device

| | Android | iOS |
|---|---|---|
| **FCM** | The transport. On Android, FCM *is* push — there is no alternative. | Reached by FCM proxying to APNs, with a key you upload to the Firebase console. |
| **APNs direct** | Not applicable. | Zonai signs its own provider tokens and talks to Apple. No Firebase project involved at all. |

Configure both and each recipient is routed by its platform — see [Device Tokens](/push/device-tokens). Configure only APNs and the app is iOS-only, and needs no Firebase project anywhere in its setup. Nothing about your schema changes between the two: the same token column and the same platform column serve either route, and the choice lives entirely in `AppConfig.push`.

## Setup is not two lines, and nobody's is

FCM reaches iOS *through* APNs. "One integration covers both platforms" is true for **sending** and false for **setup** — on that route you still upload an APNs authentication key to the Firebase console before an iPhone receives anything, and it is a console-only step with no API behind it. Going direct trades that upload for a `.p8`, a Key ID and a Team ID in your config. Budget for one or the other.

| What you need | Where it comes from |
|---|---|
| A Firebase project | Android, and iOS via FCM. Its **project ID**, not its display name. |
| A service-account JSON key | Firebase console → Project settings → Service accounts. |
| An APNs auth key uploaded to Firebase | iOS via FCM only. Apple Developer → Keys → `.p8`. |
| An APNs `.p8`, Key ID, Team ID and bundle id | iOS direct only. The same kind of key, held by you instead of Google. |
| The push SDK in your client app | Zonai sends; the device has to be registered to receive. |

An Android-only app needs the first two rows. An iOS-only app going direct needs the fourth. An app on both platforms with iOS direct needs the first, second and fourth, and never touches the Firebase console's Cloud Messaging tab.

## Why this is in the framework

An app author sending FCM from an `afterCreateSuccess` hook has to get four things right: not minting an OAuth2 token per recipient, paging a recipient set without loading it into memory, surviving a restart mid-fan-out, and distinguishing a token that is *dead* from one that merely *timed out*. Each is the kind of thing frameworks exist to own, and most hand-rolled versions get at least two of them wrong quietly.

The last one matters most. A timeout that gets treated as a death deletes a live registration, and the person stops receiving notifications with nothing in any log to say why.

## What Zonai owns, and what stays yours

| Zonai | You |
|---|---|
| The `deviceToken` **column** — reads it, clears it | The table it lives on, its name, every other column |
| Paging, batching, checkpointing, backoff, retries | Which recipients a message is for (the `where`) |
| Choosing a transport per recipient, and signing for it | Declaring which platform a row belongs to |
| Classifying a rejection as permanent or transient | What a rejection *means*, via `onPushRejected` |
| `AppConfig.push`, credentials, the jobs table | When to send, cooldowns, muting, quiet hours |

Zonai never requires a particular table name, never requires a `user_id`, and never reads a column it was not pointed at.

A framework that writes into your tables is one you have to trust. That trust is optional — see [Dead Tokens](/push/dead-tokens).

## Where to go next

- [Device Tokens](/push/device-tokens) — declare the column that makes recipients findable, and the one that routes them.
- [Configuration](/push/configuration) — credentials for both routes, and the rotation cost of getting them wrong.
- [Sending](/push/sending) — naming a recipient set, and what the returned job id does and does not promise.
- [Delivery Guarantees](/push/delivery-guarantees) — read this before assuming a notification arrived.

## Not in v1

**Topics** are the right primitive for a true broadcast: one API call, no token list, no pruning, no restart-duplicate problem. When "notify everyone" comes up, the answer is topics rather than a bigger fan-out. They are deferred because they bring their own surface — subscribe, unsubscribe, per-topic auth.

**Payload localization is decided against, not deferred.** Zonai does not translate notification text. An app that needs per-locale copy builds the string before calling `push` — it already knows its user's locale, and having the framework re-derive it would mean reading columns the fan-out deliberately does not select (see [Sending](/push/sending)).

Also out of scope for now: web push, scheduled or delayed sends, delivery analytics, an in-app notification inbox, per-user preference storage, rich media attachments, and badge counts.
