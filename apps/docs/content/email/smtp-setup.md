---
title: SMTP Setup
description: Configuring SMTP credentials for transactional email delivery.
---

Zonai sends transactional email over **SMTP**. You need three things for it to work, and each one fails on its own:

1. **Credentials reach the compiled workers.** They come from `.env` at compile time.
2. **The port and TLS setting match.** Port and `ssl` are really one setting, stored in two fields.
3. **Mail servers trust your domain.** That means SPF, DKIM and DMARC records in DNS, which have nothing to do with the app.

When email doesn't send at all, the cause is usually #1 or #2. When it sends but lands in spam, the cause is #3. This page covers #1 and #2. [Production Delivery](/email/production) covers #3 and how to test each layer.

## Configure `AppConfig.email`

Set the `email` field in your config worker (`lib/src/config/db_config*.dart`) to an `EmailConfig`:

```dart in:expression
AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
  baseUrl: 'https://app.example.com',
  email: EmailConfig(
    host: const String.fromEnvironment('SMTP_HOST'),
    port: int.parse(String.fromEnvironment('SMTP_PORT', defaultValue: '587')),
    username: const String.fromEnvironment('SMTP_USERNAME'),
    password: const String.fromEnvironment('SMTP_PASSWORD'),
    from: EmailAddress(
      address: const String.fromEnvironment('SMTP_FROM_ADDRESS'),
      name: 'My App',
    ),
    ssl: const bool.fromEnvironment('SMTP_SSL'),
  ),
)
```

`baseUrl` (default `http://localhost:8080`) is not an email setting, but every link in an auth email (verify, magic link, password reset) is built from it. See [Built-in Templates](/email/built-in-templates#links-in-auth-emails).

## `EmailConfig` fields

| Field      | Type           | Required | Description                                                                          |
| ---------- | -------------- | -------- | ------------------------------------------------------------------------------------ |
| `host`     | `String`       | Yes      | SMTP server hostname or IP                                                           |
| `port`     | `int`          | Yes      | SMTP port. It must match `ssl`; see [Port and TLS](#port-and-tls-must-agree)         |
| `username` | `String`       | Yes      | SMTP auth username. Some providers use a fixed string here, not your address         |
| `password` | `String`       | Yes      | SMTP auth password or API key                                                        |
| `from`     | `EmailAddress` | Yes      | Default sender. An `Email` can override it per message                               |
| `ssl`      | `bool`         | No       | `true` = implicit TLS (port 465). `false` (the default) = STARTTLS (port 587)        |

If `from.name` is null, the sender name falls back to `AppConfig.appName`.

## Put the credentials in `.env`

Zonai reads a `.env` file for the flavor you are building and passes every key to each compiled worker as a compile-time define. See [Environment Variables](/configuration/environment-variables) for how the file is chosen per `--flavor`.

```ini
# .env — gitignored, never committed
SMTP_HOST=smtp.resend.com
SMTP_PORT=465
SMTP_SSL=true
SMTP_USERNAME=resend
SMTP_PASSWORD=re_…
SMTP_FROM_ADDRESS=alerts@example.com
```

A few things here commonly cause problems:

- **Defaults are silent.** If a key is missing, `String.fromEnvironment` returns its `defaultValue` (or `''`) and nothing warns you. A plausible but wrong value, such as your email address where Resend expects the literal `resend`, fails at SMTP `AUTH`, not at build time.
- **There is no fallback between env files.** `--flavor prod` loads `.env.prod` and nothing else. If that file is missing, the build has no defines at all, even when a plain `.env` exists.
- **Credentials are compile-time only.** The workers never read the process environment for SMTP settings, so a secret you set in your host's runtime secret store does nothing here. Change `.env` and recompile. The compiled executables contain these values, so treat `.zonai/executables/` and `build/` as sensitive.
- **Cron workers get the same defines**, so a cron that sends mail reads `SMTP_*` exactly as the config worker does.

## Port and TLS must agree

This is the setting most likely to cost you an afternoon.

`ssl: true` opens the connection with TLS from the first byte (**implicit TLS**). `ssl: false` connects in plaintext, then upgrades with **STARTTLS** if the server offers it. `ssl: false` does **not** mean "unencrypted". Every mainstream provider offers STARTTLS.

The two standard submission ports need **opposite** settings:

| Port | Server expects | `ssl` |
| ---- | -------------- | ----- |
| 465  | TLS handshake immediately | `true` |
| 587  | Plaintext greeting, then STARTTLS | `false` |

A mismatch does not fall back to something that works. With `ssl: true` against port 587, the client waits for a TLS handshake the server never starts. You get a connection timeout, and the error doesn't mention TLS. Both values look reasonable on their own, so it is worth checking the pairing in your config worker to get a useful error message:

```dart in:smtp-guard
String? smtpTransportMismatch(EmailConfig config) {
  if (config.port == 465 && !config.ssl) {
    return 'port 465 expects implicit TLS (ssl: true)';
  }
  if (config.port == 587 && config.ssl) {
    return 'port 587 expects STARTTLS (ssl: false)';
  }
  return null; // non-standard ports (2465/2587) deliberately left alone
}
```

Call it in the config worker's `main()` and throw if it returns non-null. A bad `.env` then fails at compile time, not as an unexplained timeout in production.

## Choosing a provider

Sending is a relay, so you don't need a mailbox or a mail server. You need a transactional provider and a domain whose DNS you control. You can switch providers later by changing credentials, with no code changes.

| Provider | Host | Port / `ssl` | Username | Notes |
| -------- | ---- | ------------ | -------- | ----- |
| Resend | `smtp.resend.com` | 465 / `true` | `resend` | Free tier: 3,000/month, 100/day, 1 domain |
| Brevo | `smtp-relay.brevo.com` | 587 / `false` | your Brevo login | Free tier: 300/day |
| Amazon SES | `email-smtp.<region>.amazonaws.com` | 587 / `false` | SMTP credential (not your IAM key) | Cheapest at scale; starts in a sandbox until you request production access |
| Mailgun | `smtp.mailgun.org` | 587 / `false` | domain SMTP login | |
| Mailhog (local) | `localhost` | 1025 / `false` | `''` | Catches mail, delivers nothing. See [Testing Locally](/email/testing-locally) |

Check your provider's dashboard for the exact values. The table above is a starting point.

## Without SMTP configured

If `AppConfig.email` is null, the server still starts, and every send is skipped with a warning in the server log:

```text
Cannot send email because email configuration is missing
```

This covers auth emails (verify, OTP, magic link, password reset, admin invite), `email.send(...)` from hooks and crons, `POST /email`, and `zonai db email test`. Nothing throws, and `zonai db email test` still reports the message as sent. Auth emails and `email.send(...)` are fire-and-forget, so for them this log line is the only signal you get. That makes it safe to ship email-sending code before you have credentials.

Setting `email` with an empty `host` is **not** the same thing. It is not treated as "off": the send is attempted and fails when it connects. Leave `email` unset (for example, only set it in the flavors that have credentials) until the credentials are real.

## Testing the configuration

```sh
zonai db email test --to your@email.com
```

This sends the `verify_email` template to the address, filled with placeholder values. See [Testing Locally](/email/testing-locally) for local development, and [Production Delivery](/email/production#verify-the-credentials-without-sending) for checking credentials without sending anything.
