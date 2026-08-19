---
title: Custom Templates
description: Creating and sending your own email templates.
---

{{=<% %>=}}

<!-- This page shows Mustache syntax literally, so Mustache must not read it.
     jaspr_content runs every page through MustacheTemplateEngine before the
     markdown is parsed (see main.server.dart), so a placeholder written as an
     example is treated as a real tag: the published page rendered "Hi ," where
     the code block said "Hi {NAME}," and a prose mention of a section tag
     failed the build outright with "Unclosed tag: 'preheader'", taking the
     whole docs deploy down on 2026-08-19.

     The tag above switches the delimiters away from curly braces for the
     rest of the page (it cannot be spelled out here -- writing the new
     delimiters in this comment would make the comment a tag),
     which is Mustache's own way of saying "no tags here". It renders as
     nothing. It has to come first -- before this comment -- because anything
     Mustache reads ahead of it is still a tag. Keep it at the top of any page
     that quotes Mustache. content/about.md deliberately does NOT have one: it
     uses a real {SITE_SOCIAL} loop. -->


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

```dart in:extension-purchase
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
    preheader: 'Arriving Thursday. Track it any time.',
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

## Preview Text

`preheader` is the line the inbox shows next to the subject. Leave it unset and the client picks the first visible text it finds — usually the greeting, so every message previews as `Hi Morgan,`.

It is injected into your template as `{{preheader}}`, the same way `{{appName}}` is — you never pass it in `variables`. To use it, put a hidden block at the very top of the `<body>`:

```html
<body>
  {{#preheader}}
  <div
    style="
      display: none;
      max-height: 0;
      overflow: hidden;
      mso-hide: all;
      font-size: 1px;
      line-height: 1px;
      color: transparent;
      opacity: 0;
    "
  >
    {{preheader}}&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;
  </div>
  {{/preheader}}

  <!-- visible content -->
</body>
```

Three parts, all of them load-bearing:

- **The `{{#preheader}}` section** renders nothing at all when no preheader was set, rather than leaving an empty hidden div in every message.
- **The style block** hides the text every way a client might respect — `display: none` and `max-height: 0` for most, `mso-hide: all` for Outlook, `opacity` and `color: transparent` for anything that strips the first two.
- **The trailing zero-width characters** pad out the rest of the snippet. Without them the client keeps scraping and tacks the next visible text — often a button label — onto the end of your preview line. Repeat the run until it covers roughly 100 characters.

Keep the line under ~100 characters, and do not repeat the subject: the two are shown side by side, so the preheader is a second sentence, not an echo.

The built-in templates already carry this block, and the built-in auth emails set a sensible default (`Your sign-in code expires in 10 minutes.`, and so on). Pass `preheader:` to override.

Blank counts as unset — a preheader of `''` or whitespace renders no block.

## Live Reloading

Templates are read from disk at send time. Changes take effect immediately — no recompile or server restart needed.
