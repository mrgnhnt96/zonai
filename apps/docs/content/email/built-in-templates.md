---
title: Built-in Templates
description: The seven built-in email templates, what sends each one, the variables they receive, and their default preview text.
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
     rest of the page (it cannot be spelled out here — writing the new
     delimiters in this comment would make the comment a tag),
     which is Mustache's own way of saying "no tags here". It renders as
     nothing. It has to come first — before this comment — because anything
     Mustache reads ahead of it is still a tag. Keep it at the top of any page
     that quotes Mustache. content/about.md deliberately does NOT have one: it
     uses a real {SITE_SOCIAL} loop. -->


Zonai ships seven HTML email templates. The first time you run `zonai dev` in a new project, it writes them into `emailTemplatesPath` (default `lib/src/email_templates`). They are ordinary files in your project, so edit them freely. Existing files are never overwritten. Zonai reads templates from disk at send time, so edits take effect without recompiling.

If a template file is missing (for example, a project created before that template existed), the send fails and the server log names the path it looked for: `Email template not found: …`. Copy the file from a fresh project, or create one with `zonai db email template create <name>`.

## What sends each template

| Template | Sent when | Default expiry |
| -------- | --------- | -------------- |
| `verify_email` | The default `onSignUp` hook on an auth table with an email column, `POST /auth/verify-email`, or `email.send.verifyEmail(...)` | 24 hours (`VerifyEmailConfig`) |
| `otp_code` | `POST /auth` with `type: "sendOtp"`, or `email.send.otpCode(...)` | 10 minutes (fixed) |
| `magic_link` | `POST /auth` with `type: "sendMagicLink"` | 10 minutes (`MagicLinkConfig`) |
| `password_reset` | `POST /auth/reset-password`, or `email.send.passwordReset(...)` | 10 minutes (`ResetPasswordConfig`) |
| `admin_invite` | Inviting an admin (`zonai db admin invite` or the dashboard) | 7 days |
| `confirm_change_email` | Nothing yet (see below) | |
| `login_notice` | Nothing yet (see below) | |

The expiry settings live on your [auth operations](/operations/auth-operations). OTP, magic-link and password-reset sends are limited to one per address per minute. See [Auth Rate Limits](/rate-limiting/auth-rate-limits).

> **`login_notice` and `confirm_change_email` are templates only for now.** The server does not implement `email.send.loginNotice(...)`, `email.send.magicLink(...)` or `email.send.confirmEmailChange(...)`: each one sends nothing and raises an `UnimplementedError` on the server. The default `onSignIn` hook calls `loginNotice` for auth tables with an email column, so override `onSignIn` if you don't want that failure in your logs. To send either message today, call `email.send(Email(template: 'login_notice', ...))` yourself with the variables below.

## Variables

Every template also receives **`appName`** (from `AppConfig`) and **`preheader`** (see [Preview text](#preview-text)) without you passing them. Anything you add in `variables:` is merged in as well.

| Template | Variables |
| -------- | --------- |
| `verify_email.html` | `email`, `verificationUrl`, `expiresIn`, optional `name` |
| `otp_code.html` | `email`, `otp`, `expiresIn`, optional `name` |
| `magic_link.html` | `email`, `magicLinkUrl`, `expiresIn`, optional `name` |
| `password_reset.html` | `email`, `passwordResetUrl`, `expiresIn`, optional `name` |
| `admin_invite.html` | `email`, `inviteUrl`, `expiresIn`, optional `invitedByEmail` |
| `confirm_change_email.html` | `currentEmail`, `newEmail`, `confirmChangeEmailUrl`, `expiresIn`, optional `name` |
| `login_notice.html` | `email`, `signedInAt`, optional `name` |

`expiresIn` is already formatted as text, such as `10 minutes`, `24 hours` or `7 days`.

## Links in auth emails

Verify, magic-link and password-reset links are built from **`AppConfig.baseUrl`** plus the `path` on the matching config in your auth operations (`/auth/verify-email`, `/auth/magic-link` and `/auth/reset-password` by default). A path that already starts with `http` is used as-is. The one-time token is appended as `?s=<token>`.

If `baseUrl` is still the default `http://localhost:8080`, every link in production points at localhost. See [Server Binding](/deployment/server-binding).

## Preview text

Every built-in template opens with a hidden `{{preheader}}` block. That's the line the inbox shows next to the subject. Each built-in auth email sets its own default:

| Email            | Default preview line                                   |
| ---------------- | ------------------------------------------------------ |
| `otp_code`       | `Your sign-in code expires in 10 minutes.`             |
| `magic_link`     | `Your sign-in link expires in 10 minutes.`             |
| `verify_email`   | `Confirm <address> to finish setting up your account.` |
| `password_reset` | `Your reset link expires in 10 minutes.`               |
| `admin_invite`   | `Your invite expires in 7 days.`                       |

The expiry in each line follows the expiry you configure. The OTP preview deliberately leaves out the code, because the preview line is what shows on a locked phone.

To override one, pass `preheader:` when you construct the email. If you write your own template, see [Custom Templates](/email/custom-templates#preview-text) for the markup.

## Customizing

Edit the HTML files in `emailTemplatesPath` directly. Templates use [Mustache](https://mustache.github.io/mustache.5.html). See [Custom Templates](/email/custom-templates#template-format) for the syntax and rendering rules. To preview a template with your own values without sending it, use **Preview email** in `zonai dev`.

`zonai build` copies the templates directory into the build output. Ship it alongside the binary, because production reads templates from there.
