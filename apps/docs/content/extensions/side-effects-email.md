---
title: "Side Effects: email"
description: Sending transactional email from extensions and cron jobs.
---

`email.send` provides helpers for sending transactional emails from extension hooks and cron jobs. SMTP must be configured in `AppConfig` before any email will be delivered. See [SMTP Setup](/email/smtp-setup).

## Built-in Helpers

Each method sends one of the built-in templates. The first argument is an `EmailAddress`; `table` identifies which auth table the user belongs to:

```dart in:side-effects
email.send.verifyEmail(
  EmailAddress(address: user.email),
  table: 'users',
);

email.send.loginNotice(
  EmailAddress(address: user.email),
  table: 'users',
);

email.send.passwordReset(
  EmailAddress(address: user.email),
  table: 'users',
);

email.send.magicLink(
  EmailAddress(address: user.email),
  table: 'users',
);

email.send.otpCode(
  EmailAddress(address: user.email),
  table: 'users',
);

email.send.confirmEmailChange(
  EmailAddress(address: user.email),
  table: 'users',
);
```

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
    email.send.loginNotice(
      EmailAddress(address: user.email),
      table: 'users',
    );
  }
}

UserExtensions main() => UserExtensions();
```
