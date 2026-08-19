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
