---
title: Custom Templates
description: Creating and sending your own email templates.
---

## Creating a Template

```sh
zonai db email template create order_confirmation
```

This creates `<emailTemplatesPath>/order_confirmation.html` pre-filled with the `verify_email` template as a starting point. Edit the file to fit your design.

## Template Format

Templates are plain HTML with Mustache interpolation. Include CSS inline — many email clients do not support `<style>` blocks.

```html
<!DOCTYPE html>
<html>
  <body>
    <h1>Order Confirmed</h1>
    <p>Hi {{customerName}},</p>
    <p>Your order <strong>#{{orderId}}</strong> has been confirmed.</p>
    <p>Total: {{total}}</p>
    {{#items}}
    <p>- {{name}} × {{quantity}}</p>
    {{/items}}
  </body>
</html>
```

Templates use [Mustache](https://mustache.github.io/mustache.5.html) syntax.

## Sending a Custom Template

Use `email.send(Email(...))` from any extension hook or cron job:

```dart
@override
Future<void> afterCreateSuccess(Purchase purchase, Jwt? jwt) async {
  final customer = await get.one(
    tableName: 'users',
    where: Eq('id', purchase.userId.value),
  );

  if (customer == null) return;

  email.send(Email(
    to: EmailAddress(address: customer['email'] as String),
    subject: 'Order #${purchase.id} confirmed',
    template: 'order_confirmation',
    variables: {
      'customerName': customer['name'],
      'orderId': purchase.id.value,
      'total': purchase.total,
    },
  ));
}
```

The `template` field is the filename without `.html`.

## Live Reloading

Templates are read from disk at send time. Changes take effect immediately — no recompile or server restart needed.
