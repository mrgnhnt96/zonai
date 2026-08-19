---
title: Built-in Templates
description: The six built-in email templates and when they are used.
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


Zonai ships six HTML email templates for the standard auth flows. They are stored in `emailTemplatesPath` and can be edited directly — changes take effect without recompiling.

## The Six Built-in Templates

### verify_email.html

Sent when `email.send.verifyEmail(...)` is called (typically in `onSignUp`).

| Variable          | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `email`           | The recipient's email address                        |
| `verificationUrl` | The full URL the user clicks to verify their address |
| `expiresIn`       | Human-readable expiry (e.g. `"24 hours"`)            |

### otp_code.html

Sent automatically when `POST /auth` with `type: "sendOtp"` is called.

| Variable    | Description                                 |
| ----------- | ------------------------------------------- |
| `email`     | The recipient's email address               |
| `otp`       | The numeric OTP code                        |
| `expiresIn` | Human-readable expiry (e.g. `"10 minutes"`) |

### magic_link.html

Sent automatically when `POST /auth` with `type: "sendMagicLink"` is called.

| Variable       | Description                   |
| -------------- | ----------------------------- |
| `email`        | The recipient's email address |
| `magicLinkUrl` | The full sign-in link         |
| `expiresIn`    | Human-readable expiry         |

### password_reset.html

Sent automatically when `POST /auth/reset-password` is called.

| Variable           | Description                   |
| ------------------ | ----------------------------- |
| `email`            | The recipient's email address |
| `passwordResetUrl` | The full password reset link  |
| `expiresIn`        | Human-readable expiry         |
| `name`             | The user's name (if provided) |

### confirm_change_email.html

Sent when an email address change requires confirmation.

| Variable     | Description           |
| ------------ | --------------------- |
| `email`      | The new email address |
| `confirmUrl` | The confirmation link |
| `expiresIn`  | Human-readable expiry |

### login_notice.html

Sent when `email.send.loginNotice(...)` is called (typically in `onSignIn`).

| Variable | Description                   |
| -------- | ----------------------------- |
| `email`  | The recipient's email address |

## Preview Text

Every built-in template opens with a hidden `{{preheader}}` block — the line the inbox shows next to the subject. Each built-in auth email sets its own default:

| Email            | Default preview line                              |
| ---------------- | ------------------------------------------------- |
| `otp_code`       | `Your sign-in code expires in 10 minutes.`        |
| `magic_link`     | `Your sign-in link expires in 15 minutes.`        |
| `verify_email`   | `Confirm <address> to finish setting up your account.` |
| `password_reset` | `Your reset link expires in 30 minutes.`          |
| `admin_invite`   | `Your invite expires in 3 days.`                  |

The expiry text follows whatever `expiresIn` you configure. The OTP preview deliberately omits the code itself — the preview line is what shows on a locked phone.

Pass `preheader:` when constructing the email to override any of them, and see [Custom Templates](/email/custom-templates#preview-text) for the markup if you are writing your own template.

## Customizing Templates

Edit the HTML files in `emailTemplatesPath` directly. Templates use [Mustache](https://mustache.github.io/mustache.5.html) syntax.

Templates are read at send time — no recompile needed after editing.

To create a new template, see [Custom Templates](/email/custom-templates).
