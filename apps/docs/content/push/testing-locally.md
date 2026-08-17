---
title: Testing Push Locally
description: FCM has no sandbox, so testing push means a local stand-in — and knowing exactly what that does and does not prove.
---

Email has Mailhog. Push has nothing equivalent, and the reason is worth stating before you look for one: **FCM has no sandbox.** Every endpoint Google publishes delivers to a real device. There is no address you can point a staging deployment at and watch what happens without someone's phone buzzing.

That leaves two options. They prove different things, and the difference matters.

## A local stand-in

`FcmPushCourier` takes a `baseUri`, and a service-account key's `token_uri` decides where the OAuth2 exchange goes. Point both at a local server and the entire path runs unmodified — a real signed assertion, a real token exchange, real HTTP, real classification, real pruning.

Zonai's own suite does exactly this. The stand-in is a real `HttpServer` implementing both FCM v1 endpoints, and it holds only the **public** half of a generated keypair, so it verifies the service-account assertion the way Google verifies it rather than rubber-stamping it. That check is the point: a stubbed HTTP client cannot fail it, because a stub never looks at a signature. An assertion signed with the wrong algorithm, carrying the wrong claims, or not verifiable at all looks identical to a correct one until something holding the public key inspects it.

`baseUri` is a constructor argument and **not** a `PushConfig` field, on purpose. Config is parsed from user-supplied yaml, and an endpoint override there would be a way to redirect production's notifications — access token included — by editing a config file.

### What it proves

That the request you build is one a correct FCM implementation accepts, and that an error body FCM documents produces the right outcome on the right row.

### What it does not prove

**That Google behaves the way Google documents.** A stand-in written from the documentation and code written from the same documentation share any mistake in it silently, and go green together. A local run is not "push is verified end to end", and reading it that way is how a wrong classification reaches production with a full test suite behind it.

## Checking credentials before a device exists

A local stand-in never touches your real key, so it cannot tell you whether that key works. Push credentials fail in three ways that look identical from the outside — wrong project, missing IAM role, FCM API not enabled — and all three arrive as "notifications just don't show up".

Zonai ships a probe that asks Google directly:

```sh
dart run tool/fcm_probe.dart /etc/my-app/fcm-service-account.json
```

It sends to a token FCM has never issued. Nothing reaches a phone and nothing is pruned; the **error is the diagnosis**. A permanent rejection is the healthy answer — it means the credentials worked and FCM got as far as judging the token, which is the same path a real dead registration takes. A `403 PERMISSION_DENIED` means the service account lacks the **Firebase Cloud Messaging API Admin** role, or belongs to a different project than you think.

That last case is the common one, and it is genuinely hard to spot any other way: a Play/`androidpublisher` service account — the kind Google Play billing and RevenueCat hand you — is a real key, in a real Google project, that simply is not the FCM one. It looks correct in every respect except the one that matters.

## A real send

The only thing that closes the gap above, and the reason it is worth the setup.

You need a Firebase project, an app registered in it, and a service account holding the **Firebase Cloud Messaging API Admin** role. An `androidpublisher` service account — the kind Google Play billing and RevenueCat use — is not that one, and usually is not even in the same project.

Then send to two devices:

- one with the app installed
- one where the app has been **deliberately uninstalled**

The uninstalled one must prune. The installed one must not. That single test is what validates the classification table the whole feature rests on, because it is the only test where FCM itself — not your reading of its documentation — decides which row gets cleared.

For iOS, upload an APNs auth key to the Firebase console first. See [Configuration](/push/configuration) for which `.p8` that is, and which one it is easy to mistake for it.
