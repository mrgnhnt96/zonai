---
title: Testing Email Locally
description: How to test email templates and delivery in development.
---

## Previewing in the Browser

`zonai dev` includes a built-in email previewer. Open the **Email** tab in the TUI to browse all email templates and open them in your browser — no SMTP setup required.

## Using a Local SMTP Catcher

[Mailhog](https://github.com/mailhog/MailHog) captures outgoing email in development and shows it in a web UI — no real delivery happens.

**Install with Docker:**

```sh
docker run -p 1025:1025 -p 8025:8025 mailhog/mailhog
```

**Install on macOS:**

```sh
brew install mailhog && mailhog
```

Then configure `EmailConfig` in your dev flavor:

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

All emails sent while the server is running in dev mode appear at `http://localhost:8025`.

## Sending a Test Email

```sh
zonai db email test --to your@email.com
```

This sends the default `verify_email` template and prints whether delivery succeeded. Use `--template` to test a specific template:

```sh
zonai db email test --to your@email.com --template order_confirmation
```

Placeholder values are used for template variables — check the rendered result in Mailhog.

## Template Variables

If a Mustache variable is missing from the data map, it renders as an empty string without error. Verify all expected variables appear in the Mailhog preview before deploying.

## Before Deploying

Test with your real SMTP provider using a staging recipient:

Test with your real SMTP provider using a staging recipient:

1. Send a test email with `zonai db email test`
2. Confirm delivery in your inbox
3. Check that all links work and HTML renders correctly in multiple email clients
