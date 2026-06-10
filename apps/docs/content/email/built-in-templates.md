---
title: Built-in Templates
description: The six built-in email templates and when they are used.
---

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

## Customizing Templates

Edit the HTML files in `emailTemplatesPath` directly. Templates use [Mustache](https://mustache.github.io/mustache.5.html) syntax.

Templates are read at send time — no recompile needed after editing.

To create a new template, see [Custom Templates](/email/custom-templates).
