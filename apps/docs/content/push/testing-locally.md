---
title: Testing Push Locally
description: FCM has no sandbox and APNs does, so how far you can get before a real phone is involved depends on which route you are on.
---

Email has Mailhog. Push has nothing equivalent, and how close you can get depends on the transport:

| | A test address that does not reach a phone |
|---|---|
| **FCM** | None. Every endpoint Google publishes delivers to a real device. |
| **APNs** | `api.sandbox.push.apple.com`, reached with `useSandbox: true`. |

So there are three things you can do, and they prove different things. The difference is the whole point of this page.

## A local stand-in

Both couriers take their endpoint as a **constructor argument**, so a test can point them at a local server and the entire path runs unmodified — real signing, real HTTP, real classification, real pruning.

- `FcmPushCourier` takes a `baseUri`, and a service-account key's `token_uri` decides where the OAuth2 exchange goes.
- `ApnsPushCourier` takes a `connect` function. APNs is HTTP/2-only and the courier multiplexes one connection, so the stand-in has to be a real HTTP/2 server rather than a stubbed client — that shape does not survive being replaced by canned responses.

Zonai's own suite does exactly this, and both stand-ins hold only the **public** half of a generated keypair, so each verifies the credential the way the real service verifies it rather than rubber-stamping it. That check is the point: a stubbed HTTP client cannot fail it, because a stub never looks at a signature. An assertion signed with the wrong algorithm, carrying the wrong claims, or not verifiable at all looks identical to a correct one until something holding the public key inspects it.

The two are also deliberately not the same key: **Apple signs with ES256 and Google with RS256**, and handing one an algorithm's key of the other kind fails deep inside the JWT library as a raw cast error rather than as anything that names the mistake.

The endpoint override is a constructor argument and **not** a `PushConfig` field, on purpose. Config is parsed from user-supplied yaml, and an endpoint override there would be a way to redirect production's notifications — access token included — by editing a config file.

### What it proves

That the request you build is one a correct implementation accepts, and that an error body the service documents produces the right outcome on the right row.

### What it does not prove

**That Google and Apple behave the way Google and Apple document.** A stand-in written from the documentation and code written from the same documentation share any mistake in it silently, and go green together. A local run is not "push is verified end to end", and reading it that way is how a wrong classification reaches production with a full test suite behind it.

This is not hypothetical. The FCM classification table on [Dead Tokens](/push/dead-tokens) was wrong three times when written from the docs, every time in the direction that silently disables pruning.

## The APNs sandbox

The strongest check available without a phone buzzing, and it exists on this route only.

```dart no-analyze
apns: ApnsConfig(
  credentials: ApnsCredentials.file('/etc/my-app/AuthKey_ABCD123456.p8'),
  keyId: 'ABCD123456',
  teamId: 'U2G2XV3688',
  bundleId: 'com.example.myapp',
  useSandbox: true,
),
```

That is **real Apple** judging a real ES256 provider token signed by your real key. It answers the questions a stand-in cannot: whether the key, Key ID and Team ID actually belong together, and whether the bundle id is a registered, push-enabled App ID.

Two things to know before it confuses you:

- **Sandbox and production are separate worlds.** A token issued to a development build is unknown to production and vice versa. The symptom of mixing them is `BadDeviceToken` on a token that is perfectly valid — just not here.
- **A simulator token is accepted and dropped.** APNs takes the send and nothing arrives, which looks exactly like a broken integration. A simulator cannot verify delivery; `xcrun simctl push` is how you exercise the app's receive side, and it never touches Apple.

## Checking credentials before a device exists

A local stand-in never touches your real key, so it cannot tell you whether that key works. FCM credentials fail in three ways that look identical from the outside — wrong project, missing IAM role, FCM API not enabled — and all three arrive as "notifications just don't show up".

Zonai ships a probe that asks Google directly:

```sh
dart run tool/fcm_probe.dart /etc/my-app/fcm-service-account.json
```

It sends to a token FCM has never issued. Nothing reaches a phone and nothing is pruned; the **error is the diagnosis**. A permanent rejection is the healthy answer — it means the credentials worked and FCM got as far as judging the token, which is the same path a real dead registration takes. A `403 PERMISSION_DENIED` means the service account lacks the **Firebase Cloud Messaging API Admin** role, or belongs to a different project than you think.

That last case is the common one, and it is genuinely hard to spot any other way: a Play/`androidpublisher` service account — the kind Google Play billing and RevenueCat hand you — is a real key, in a real Google project, that simply is not the FCM one. It looks correct in every respect except the one that matters.

The APNs equivalent is the sandbox above: send to a made-up token and read the `reason`. `InvalidProviderToken` is a credentials problem, `TopicDisallowed` is a bundle id your team does not own, and `BadDeviceToken` means everything except the token was right.

## A real send

The only thing that closes the gap above, and the reason it is worth the setup.

Send to two devices:

- one with the app installed
- one where the app has been **deliberately uninstalled**

The uninstalled one must prune. The installed one must not. That single test is what validates the classification table the whole feature rests on, because it is the only test where the push service itself — not your reading of its documentation — decides which row gets cleared.

For FCM you need a Firebase project, an app registered in it, and a service account holding the **Firebase Cloud Messaging API Admin** role. An `androidpublisher` service account is not that one, and usually is not even in the same project. For iOS via FCM, upload an APNs auth key to the Firebase console first — see [Configuration](/push/configuration) for which `.p8` that is, and which one it is easy to mistake for it.

### Two things that will cost you an hour each on iOS

Both are about *observing* the notification rather than sending it, and both look exactly like a lost notification.

- **A push is only visible with the app backgrounded.** While your app is frontmost, iOS suppresses the banner and hands the notification to the app instead. A foreground test looks like nothing arrived.
- **Test a release build.** A debug build cannot launch standalone on modern iOS — it needs the Flutter tooling attached — so `flutter build ios --release` is what you install on the phone.
