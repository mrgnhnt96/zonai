---
title: Testing Email Locally
description: How to test email templates and delivery in development.
---

## Previewing in the browser

`zonai dev` has two email actions in its menu, and neither needs SMTP:

- **Preview email** renders a template with variable values you type and opens it in your browser. Nothing is sent.
- **Create email template** creates a new template file, the same as `zonai db email template create <name>`.

A third action, **Send test email**, sends a rendered template to a real inbox through your configured SMTP server.

## Using a local SMTP catcher

[Mailhog](https://github.com/mailhog/MailHog) accepts outgoing email in development and shows it in a web UI. Nothing is actually delivered.

**Run with Docker:**

```sh
docker run -p 1025:1025 -p 8025:8025 mailhog/mailhog
```

**Or on macOS:**

```sh
brew install mailhog && mailhog
```

Then point `EmailConfig` at it in your dev flavor:

```dart in:app-config
// db_config.dev.dart
email: EmailConfig(
  host: 'localhost',
  port: 1025,
  username: '',
  password: '',
  from: EmailAddress(address: 'dev@localhost', name: 'Dev'),
),
```

Every email the server sends then appears at `http://localhost:8025`. Also set `baseUrl` to the URL your browser uses, so the links in auth emails open your local server.

## Sending a test email

```sh
zonai db email test --to your@email.com
```

This sends the `verify_email` template with placeholder values for every built-in variable. Use `--template` to choose another template:

```sh
zonai db email test --to your@email.com --template order_confirmation
```

The command reports success as soon as the send returns, including when `AppConfig.email` is not set. In that case the send was skipped and the log shows `Cannot send email because email configuration is missing`. See [SMTP Setup](/email/smtp-setup#without-smtp-configured).

## Template variables

A variable missing from the data renders as an empty string, with no error. Check that every expected value appears in the preview or in Mailhog before you deploy.

## When nothing arrives

- **Look in the server log.** Auth emails and `email.send(...)` are fire-and-forget, so failures only show up there: a missing config, a missing template file (`Email template not found: <path>`), or an SMTP error.
- **Check that the template file exists** at the path the log names. It is resolved against `emailTemplatesPath`.
- **Timeouts usually mean a port/TLS mismatch.** See [Port and TLS must agree](/email/smtp-setup#port-and-tls-must-agree).

## Before deploying

1. Send a test through your real SMTP provider with `zonai db email test`, to an inbox you control.
2. Check that the links work, and that the HTML renders correctly in several email clients.
3. Work through [Production Delivery](/email/production) to verify your domain's DNS and deliverability.
