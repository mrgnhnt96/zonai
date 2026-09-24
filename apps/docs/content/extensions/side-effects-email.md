---
title: "Side Effects: email"
description: Sending transactional email from extensions and cron jobs.
---

`email.send` provides helpers for sending transactional emails from extension hooks and cron jobs. SMTP must be configured in `AppConfig` before any email will be delivered. See [SMTP Setup](/email/smtp-setup).

## Built-in Helpers

Each method sends one of the [built-in templates](/email/built-in-templates). The first argument is an `EmailAddress`, and `table` names the auth table the user belongs to:

```dart in:side-effects
email.send.verifyEmail(
  EmailAddress(address: user.email),
  table: 'users',
);

email.send.passwordReset(
  EmailAddress(address: user.email),
  table: 'users',
);

email.send.otpCode(
  EmailAddress(address: user.email),
  table: 'users',
);
```

> **`loginNotice`, `magicLink` and `confirmEmailChange` also exist, but the server does not implement them yet.** Calling one sends nothing and raises an `UnimplementedError` on the server. The default `onSignIn` hook calls `loginNotice` for auth tables with an email column, so override `onSignIn` to stop it. To send a sign-in notice today, use `email.send(Email(template: 'login_notice', ...))`, as shown below.

All helpers accept an optional `variables` map to pass extra data to the template.

## Sending Custom Emails

Use `email.send(Email(...))` to send a custom template:

```dart in:side-effects
email.send(Email(
  to: EmailAddress(address: user.email),
  subject: 'Your order is confirmed',
  template: 'order_confirmation',
  variables: {
    'orderId': purchase.id,
    'total': purchase.total,
    'status': purchase.status,
  },
));
```

The `template` field is the filename (without `.html`) from `emailTemplatesPath`. See [Custom Templates](/email/custom-templates).

## Threading

Pass `thread` on multiple related emails (e.g. OTP resends) to group them in the user's inbox:

```dart in:side-effects
email.send(Email(
  to: EmailAddress(address: user.email),
  subject: 'New sign-in code',
  template: 'otp_code',
  variables: {'otp': newCode},
  thread: Email.createThread('otp:users:${user.email}', continueThread: true),
));
```

## When Email Sends

`email.send.*` is fire-and-forget — it does not await delivery and does not block the HTTP response. If SMTP delivery fails, the error is logged but the original request still succeeds. There is no built-in retry.

## Example

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserExtensions extends Extension<User>
    with AuthExtension<User> {
  UserExtensions() : super(users);

  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {
    email.send.verifyEmail(
      EmailAddress(address: user.email),
      table: 'users',
    );
  }

  @override
  Future<void> onSignIn(User user, Jwt? jwt) async {
    email.send(Email(
      to: EmailAddress(address: user.email),
      subject: 'New sign-in',
      template: 'login_notice',
      variables: {
        'email': user.email,
        'signedInAt': DateTime.now().toUtc().toIso8601String(),
      },
    ));
  }
}

UserExtensions main() => UserExtensions();
```
