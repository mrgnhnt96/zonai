---
title: Webhooks
description: Receive third-party callbacks at POST /hooks/<name>, verify their signature, and write rows as the server.
---

Webhooks let a third party (Resend, Stripe, Clerk, ...) call your app. Each webhook is a Dart class with a `name`, and Zonai routes `POST /hooks/<name>` to it. The handler gets the request body exactly as it was sent, plus the headers and the caller's IP. It answers with a status code. Like cron jobs, it can read, write and send email as the server.

Use webhooks for inbound email, delivery and bounce notices, payment events, or anything else a service pushes to you. For work your own clients trigger, use [operations](/operations/overview) or [extensions](/extensions/overview).

## What You Need

1. A `.dart` file per webhook under `webhooksPath` (default `lib/src/webhooks`, set in [`zonai.yaml`](/configuration/zonai-yaml)). Subdirectories are searched too.
2. In it, a class extending `Webhook` and a top-level `main()` returning an instance.
3. `zonai serve` (or `zonai dev`) running. It compiles the webhooks worker, starts it with the HTTP server, and recompiles when a file under `webhooksPath` changes. `zonai compile` compiles it without serving.

```dart in:project-file
import 'dart:io';

import 'package:zonai_schema/zonai_schema.dart';

final class ResendWebhook extends Webhook {
  const ResendWebhook() : super(name: 'resend');

  @override
  Future<WebhookResponse> handle(WebhookRequest request) async {
    final signature = WebhookSignature(
      Platform.environment['RESEND_WEBHOOK_SECRET']!,
    );
    if (!signature.isValid(request.body, request.headers)) {
      return const WebhookResponse(401);
    }

    final event = request.json! as Map<String, Object?>;
    mutate.create.one(
      tableName: 'email_events',
      object: {'type': event['type'], 'payload': request.text},
    );

    return const WebhookResponse.ok();
  }
}

ResendWebhook main() => const ResendWebhook();
```

Point the provider at `https://<your-host>/hooks/resend`. Names must be unique, and a name with no webhook answers `404`.

## The Request

| Field     | What it holds                                                                 |
| --------- | ----------------------------------------------------------------------------- |
| `body`    | The body bytes exactly as received                                            |
| `headers` | Request headers, names lower-cased, a repeated header joined with `, `        |
| `ip`      | The caller's IP, read the same way as for [rate limits](/rate-limiting/trusted-proxies) |
| `text`    | `body` decoded as UTF-8                                                       |
| `json`    | `body` decoded as JSON. Throws a `FormatException` when it is not JSON        |

## Verifying the Sender

`POST /hooks/<name>` needs no token: the sender cannot hold a Zonai session. Anyone who knows the URL can call it, so **check every delivery yourself** before acting on it.

`WebhookSignature` verifies the Svix / [Standard Webhooks](https://www.standardwebhooks.com) scheme, which Resend, Clerk and Svix use. Pass it the signing secret as the provider shows it (`whsec_...`):

- `isValid(body, headers)` returns `true` or `false`.
- `check(body, headers)` returns why a delivery failed (`missingHeaders`, `invalidTimestamp`, `timestampOutOfTolerance`, `noMatchingSignature`), or `null` when it passes.
- `verify(body, headers)` throws a `WebhookSignatureException` instead.

It reads the `svix-*` or `webhook-*` headers, compares signatures in constant time, and refuses timestamps more than 5 minutes from now in either direction (set `tolerance:` to change that). Verify against `request.body`, never against a re-encoded `json`: re-encoding changes the bytes and the signature no longer matches.

Keep the secret out of source. Set it as an environment variable on the server process; the webhooks worker inherits the server's environment. See [Environment Variables](/configuration/environment-variables).

## The Response

`WebhookResponse(status, body: ...)` sets the status code, and `WebhookResponse.ok()` is a `200`. A `body` is sent as `text/plain`. Senders rarely read it, but it shows up in their delivery logs.

Most providers retry a delivery that does not get a `2xx`. Answer `2xx` for events you handled or chose to ignore, and a `4xx` for a bad signature.

## Side Effects

A webhook has the same `get`, `mutate`, `email`, `push` and `logger` globals as a [cron job](/cron-jobs/side-effects), and they all run as the `CronJwt` server identity:

- **Writes go past ordinary access.** `CronJwt` has admin edit access, so the default table rules let it write any table, admin-only ones included. Rules still run: a `canCreate` (or `canUpdate`, `canDelete`) you override without calling `super` decides for webhooks too, and refusing admins refuses them.
- **Writes are queued** and commit after `handle` returns. If `handle` throws, they are dropped and the caller gets a `500`, so a provider's retry does not double-write.
- **Emails are sent when you call `email.send`**, not when `handle` returns. A throw after that does not take the email back.
- **Reads run immediately**, and do not see this delivery's queued writes.

## Limits

- **Answer within 10 seconds.** A delivery that takes longer fails with a `503` and its writes are dropped. Do slow work later: save the event and let a [cron job](/cron-jobs/overview) process it.
- **Rate limited per IP.** All webhooks share one counter per caller IP, at the [default policy](/rate-limiting/overview#default-policy) of 100 requests per minute. Behind a proxy, configure [trusted proxies](/rate-limiting/trusted-proxies) or every provider shares the proxy's counter.
- **Not in the generated client.** Your apps never call `/hooks`, so the [Dart client](/dart-client/overview) has no method for it.
- **Always a worker process.** Like crons, webhooks run in their own worker even when the project binary links your operations and rules in-process.

## Testing Locally

Send a delivery with `curl`. A handler that checks a signature will answer `401` to it, which shows the route is reached:

```bash
curl -i -X POST http://localhost:8080/hooks/resend \
  -H 'content-type: application/json' \
  --data-binary '{"type": "email.received"}'
```

To test the signed path, sign a body yourself with `WebhookSignature.sign(id, timestamp, body)` and send the result as the `svix-signature` header with matching `svix-id` and `svix-timestamp` headers. Or point the provider at a tunnel to your machine.

## Related

- [Cron Jobs](/cron-jobs/overview)
- [Side Effects in Cron Jobs](/cron-jobs/side-effects)
- [Workers](/core-concepts/workers)
- [Rate Limiting](/rate-limiting/overview)
