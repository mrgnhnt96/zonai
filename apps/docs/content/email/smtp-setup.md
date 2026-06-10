---
title: SMTP Setup
description: Configuring SMTP credentials for transactional email delivery.
---

Set the `email` field in `AppConfig` to an `EmailConfig` instance to enable transactional email:

```dart
AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
  email: EmailConfig(
    host: const String.fromEnvironment('SMTP_HOST'),
    port: int.parse(String.fromEnvironment('SMTP_PORT', defaultValue: '587')),
    username: const String.fromEnvironment('SMTP_USERNAME'),
    password: const String.fromEnvironment('SMTP_PASSWORD'),
    from: EmailAddress(
      address: 'no-reply@myapp.com',
      name: 'My App',
    ),
    ssl: false,
  ),
)
```

## EmailConfig Fields

| Field      | Type           | Required | Description                                             |
| ---------- | -------------- | -------- | ------------------------------------------------------- |
| `host`     | `String`       | Yes      | SMTP server hostname                                    |
| `port`     | `int`          | Yes      | SMTP port (587 STARTTLS, 465 SSL, 25 plain)             |
| `username` | `String`       | Yes      | SMTP auth username                                      |
| `password` | `String`       | Yes      | SMTP auth password or API key                           |
| `from`     | `EmailAddress` | Yes      | Sender address and display name                         |
| `ssl`      | `bool`         | No       | Use SSL/TLS (default: `false`; use `true` for port 465) |

All credentials should come from `String.fromEnvironment` — never hard-code secrets in source files. See [Environment Variables](/configuration/environment-variables).

## Common Email Providers

**SendGrid**

```dart
host: 'smtp.sendgrid.net',
port: 587,
username: 'apikey',
password: const String.fromEnvironment('SENDGRID_API_KEY'),
```

**Mailgun**

```dart
host: 'smtp.mailgun.org',
port: 587,
username: const String.fromEnvironment('MAILGUN_USERNAME'),
password: const String.fromEnvironment('MAILGUN_PASSWORD'),
```

**AWS SES**

```dart
host: 'email-smtp.us-east-1.amazonaws.com',
port: 587,
username: const String.fromEnvironment('SES_ACCESS_KEY_ID'),
password: const String.fromEnvironment('SES_SECRET_KEY'),
```

**Mailhog (local dev)**

```dart
host: 'localhost',
port: 1025,
username: '',
password: '',
from: EmailAddress(address: 'dev@localhost', name: 'Dev'),
```

## Testing the Configuration

After configuring SMTP, send a test email:

```sh
zonai db email test --to your@email.com
```

This sends a test message and prints whether delivery succeeded. See [Testing Locally](/email/testing-locally) for local dev setup.

## Without SMTP Configured

If `email` is not set in `AppConfig`:

- `email.send.*` calls silently do nothing
- Auth flows that trigger email (verify-email, password reset, OTP, magic link) will not deliver messages

The server still starts. Email errors only occur at send time.
