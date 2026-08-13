---
title: Email
description: Sending transactional emails from the Dart client.
---

The `email` property on `ZonaiClient` wraps the server's email endpoints. The
server handles template rendering and SMTP delivery — the client only needs to
supply the body.

See [Email](/email/smtp-setup) for server-side SMTP configuration and
[Built-in Templates](/email/built-in-templates) for available template variables.

## Send a Generic Email

```dart in:client
await client.email.send(body: Email(
  to: EmailAddress(address: 'user@example.com'),
  subject: 'Welcome',
  template: 'welcome',
  variables: {'name': 'Alice'},
));
```

## Send an OTP Code

```dart in:client
await client.email.sendOtp(email: SendOtpEmail(
  to: EmailAddress(address: 'user@example.com'),
  table: 'users',
  code: '123456',
  expiresIn: const Duration(minutes: 10),
));
```

## Send a Magic Link

```dart in:client
await client.email.sendMagicLink(email: SendMagicLinkEmail(
  to: EmailAddress(address: 'user@example.com'),
  table: 'users',
  magicLinkUrl: 'https://myapp.com/verify?token=abc',
  expiresIn: const Duration(minutes: 15),
));
```

## Send a Verification Email

```dart in:client
await client.email.sendVerifyEmail(email: SendVerifyEmailEmail(
  to: EmailAddress(address: 'user@example.com'),
  table: 'users',
  verificationUrl: 'https://myapp.com/verify-email?token=abc',
  expiresIn: const Duration(hours: 24),
));
```

## Send a Password Reset

```dart in:client
await client.email.sendPasswordReset(email: SendResetPasswordEmail(
  to: EmailAddress(address: 'user@example.com'),
  table: 'users',
  passwordResetUrl: 'https://myapp.com/reset-password?token=abc',
  expiresIn: const Duration(hours: 1),
));
```

<Info>

The email endpoints require the caller to be authenticated, except when the
server is configured to allow unauthenticated email sends via rules. Ensure a
valid token is stored before calling these methods.

</Info>
