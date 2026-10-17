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

> **`loginNotice`, `magicLink` and `confirmEmailChange` also exist, but the server does not implement them yet.** Calling one sends nothing: the server skips it, logs a warning once per process, and the request carries on. The default `onSignIn` hook calls `loginNotice` for auth tables with an email column, so override `onSignIn` to stop the warning. To send a sign-in notice today, use `email.send(Email(template: 'login_notice', ...))`, as shown below.

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

## Replying to an Email

To answer a message someone sent you, so the reply lands in their existing conversation, pass that message's `Message-ID` as `inReplyTo`. Pass `references` too when you have the whole chain. The last id in it should be the message you are answering. These headers override the ones `thread` would set.

To match the recipient's next reply back to this message, give it a `messageId` of your own and store it. `email.send` doesn't return anything, so the id has to come from you. `Email.createMessageId` makes a unique one on your sending domain. `replyTo` sends replies to an address other than `from`, such as an inbound mailbox:

```dart in:side-effects
// The Message-ID of the email being answered, stored when it arrived.
const clientMessageId = '<CAF1x2y3@mail.example.com>';

final messageId = Email.createMessageId('support@example.com');
// Store `messageId` with the conversation; the client's reply quotes it in
// its own In-Reply-To.

email.send(Email(
  to: EmailAddress(address: user.email),
  replyTo: EmailAddress(address: 'inbox@example.com', name: 'Support'),
  subject: 'Re: Your question',
  template: 'support_reply',
  messageId: messageId,
  inReplyTo: clientMessageId,
  references: [clientMessageId],
  text: 'Thanks for writing in. We have updated your booking.',
));
```

A message-id must be `local@domain`, with or without the angle brackets, and must not contain whitespace or a second `@`. An id that breaks these rules is refused, which makes it a `400` over HTTP.

`text` adds a plain-text part next to the HTML, so clients that prefer plain text don't have to strip tags. It is sent exactly as written: it is not rendered as Mustache, and the `preheader` is not added to it.

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
