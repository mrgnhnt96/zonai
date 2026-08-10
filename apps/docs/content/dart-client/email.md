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

```dart
await client.email.send(body: Email(
  to: 'user@example.com',
  subject: 'Welcome',
  template: 'welcome',
  data: {'name': 'Alice'},
));
```

## Send an OTP Code

```dart
await client.email.sendOtp(email: SendOtpEmail(
  to: 'user@example.com',
  otp: '123456',
));
```

## Send a Magic Link

```dart
await client.email.sendMagicLink(email: SendMagicLinkEmail(
  to: 'user@example.com',
  link: 'https://myapp.com/verify?token=...',
));
```

## Send a Verification Email

```dart
await client.email.sendVerifyEmail(email: SendVerifyEmailEmail(
  to: 'user@example.com',
  link: 'https://myapp.com/verify-email?token=...',
));
```

## Send a Password Reset

```dart
await client.email.sendPasswordReset(email: SendResetPasswordEmail(
  to: 'user@example.com',
  link: 'https://myapp.com/reset-password',
));
```

<Info>

The email endpoints require the caller to be authenticated, except when the
server is configured to allow unauthenticated email sends via rules. Ensure a
valid token is stored before calling these methods.

</Info>
