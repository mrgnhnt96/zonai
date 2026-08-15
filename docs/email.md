# Email templating and sending

Zonai sends transactional email over **SMTP**. HTML bodies come from **Mustache** templates in your project; the runtime renders a template with variables, then delivers the message through the configured mail server.

This page covers the in-app API. For getting a real provider, DNS, and credentials working end to end — including the port/TLS pairing that `port` and `ssl` below understate — see **[sending-email.md](sending-email.md)**.

If `AppConfig.email` is missing, send attempts are skipped and a warning is logged — useful for local dev without SMTP credentials.

## SMTP configuration

Add an `EmailConfig` to your config worker (`lib/src/config/db_config*.dart`):

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: '...',
    jwtSecret: '...',
    baseUrl: 'https://app.example.com',
    email: EmailConfig(
      host: 'smtp.example.com',
      port: 587,
      username: 'app@example.com',
      password: const String.fromEnvironment('SMTP_PASSWORD'),
      from: EmailAddress(address: 'app@example.com', name: 'My App'),
      ssl: false,
    ),
  );
}
```

| Field      | Purpose                                  |
| ---------- | ---------------------------------------- |
| `host`     | SMTP server hostname or IP               |
| `port`     | SMTP port — paired with `ssl`, see [sending-email.md](sending-email.md#step-5--make-the-port-and-tls-mode-agree) |
| `username` | SMTP auth username                       |
| `password` | SMTP auth password                       |
| `from`     | Default sender address and optional name |
| `ssl`      | Use implicit TLS (default `false`)       |

Load secrets from env defines at compile time — see **[config-and-env-flavors.md](config-and-env-flavors.md#using-env-in-config-example)**. Recompile config after changing `.env` values.

## Template directory

HTML templates live under **`emailTemplatesPath`** (default `lib/src/email_templates`, overridable in `zonai.yaml`):

```yaml
emailTemplatesPath: lib/src/email_templates
```

Each send references a template **by filename without `.html`**. For example, `template: 'verify_email'` loads `lib/src/email_templates/verify_email.html`.

The playground app ships starter templates you can copy:

```text
lib/src/email_templates/
  verify_email.html
  otp_code.html
  magic_link.html
  password_reset.html
  confirm_change_email.html
  login_notice.html
```

## Mustache templating

Templates use [Mustache](https://mustache.github.io/) syntax via the `mustache_template` package. Rendering is **lenient** — missing variables become empty strings instead of throwing.

Common patterns in the built-in templates:

| Syntax                  | Meaning                              |
| ----------------------- | ------------------------------------ |
| `{{variable}}`          | Insert a value                       |
| `{{#name}} … {{/name}}` | Block rendered when `name` is truthy |
| `{{^name}} … {{/name}}` | Block rendered when `name` is falsy  |

Every rendered email automatically receives **`appName`** from `AppConfig`, even if you do not pass it in `variables`.

Example snippet:

```html
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Your code is <strong>{{otp}}</strong>. It expires in {{expiresIn}}.</p>
<p>Sent by {{appName}}</p>
```

## Built-in templates and variables

These templates match the auth email classes in `zonai_schema`. Override the HTML files in your project to customize branding and copy.

| Template file               | Used by                   | Variables (besides `appName`)                                                                 |
| --------------------------- | ------------------------- | --------------------------------------------------------------------------------------------- |
| `verify_email.html`         | Email verification        | `email`, `verificationUrl`, `expiresIn`, optional `name`                                      |
| `otp_code.html`             | OTP sign-in / sign-up     | `email`, `otp`, `expiresIn`, optional `name`                                                  |
| `magic_link.html`           | Magic-link sign-in        | `email`, `magicLinkUrl`, `expiresIn`, optional `name`                                         |
| `password_reset.html`       | Password reset            | `email`, `passwordResetUrl`, `expiresIn`, optional `name`                                     |
| `confirm_change_email.html` | Email change confirmation | `currentEmail`, `newEmail`, `confirmChangeEmailUrl`, `expiresIn`, optional `name`             |
| `login_notice.html`         | Sign-in security notice   | `email`, `signedInAt`, optional `name`, `location`, `ipAddress`, `device`, `secureAccountUrl` |

Link URLs in auth emails are built from **`AppConfig.baseUrl`** plus the path from [`AuthOperations`](operations.md#auth-collections) (`verifyEmailConfig`, `magicLinkConfig`, `resetPasswordConfig`). See **[server-binding.md](server-binding.md#public-urls-in-app-config-baseurl)**.

## How email is sent

```text
Template + variables  →  Mustache render  →  SMTP (Courier)
```

**Courier** (`apps/zonai/lib/src/email/courier.dart`) resolves config, reads the template file, renders HTML, and sends via the `mailer` package.

### Auth flows (automatic)

The framework sends email when users trigger auth endpoints:

| Flow           | Template         | Trigger                                 |
| -------------- | ---------------- | --------------------------------------- |
| Verify email   | `verify_email`   | Sign-up hook, `POST /auth/verify-email` |
| OTP            | `otp_code`       | OTP auth request                        |
| Magic link     | `magic_link`     | Magic-link auth request                 |
| Password reset | `password_reset` | Password reset request                  |

These use typed helpers such as `SendVerifyEmailEmail` and `SendOtpEmail`, which set the subject, template name, thread id, and default variables for you.

### Custom email

Construct an `Email` and send it:

```dart no-analyze
final message = Email(
  to: EmailAddress(address: 'user@example.com', name: 'Ada'),
  subject: 'Welcome',
  template: 'verify_email',
  variables: {
    'name': 'Ada',
    'email': 'user@example.com',
    'verificationUrl': 'https://app.example.com/auth/verify-email?s=...',
    'expiresIn': '24 hours',
  },
);

await zonaiDB.sendEmail(message);
```

From HTTP, clients can `POST /email` with an `Email` JSON body (same shape as `Email.toJson()`).

Per-message overrides:

| Field       | Purpose                                           |
| ----------- | ------------------------------------------------- |
| `from`      | Override default sender from `EmailConfig.from`   |
| `thread`    | Group related messages in the same email thread   |
| `variables` | Mustache data merged with auto-injected `appName` |

Use `Email.createThread('my-thread-id')` for the first message in a conversation and `Email.createThread('my-thread-id', continueThread: true)` for follow-ups (for example a resent OTP). Courier sets `Message-ID`, `In-Reply-To`, and `References` headers accordingly.

### Extensions

Inside extension hooks, use the global **`email`** API to queue transactional mail as a side effect (applied after the main transaction). See **[extensions.md](extensions.md#side-effects-get-mutate-and-email)**.

Built-in helpers on `email.send`:

| Method               | Purpose              |
| -------------------- | -------------------- |
| `verifyEmail`        | Email verification   |
| `optCode`            | OTP code             |
| `magicLink`          | Magic-link sign-in   |
| `passwordReset`      | Password reset link  |
| `loginNotice`        | Login notification   |
| `confirmEmailChange` | Email change confirm |

Pass `collection:` and optional `variables:` for extra template data. Auth collections with **`HasEmail`** get default verify-email and login-notice behavior from [`AuthExtension`](extensions.md#default-email-behavior) unless you override those hooks.

For full control over subject, template, and variables, send a custom `Email` from an extension via the underlying send path documented in extensions.

## Testing locally

1. Set `email` in your config worker and provide SMTP credentials (for Gmail, use an app password via `String.fromEnvironment`).
2. Set `baseUrl` to the URL your browser uses for auth links.
3. Copy or customize templates under `emailTemplatesPath`.
4. Send a test message — for example during `dart run zonai db test`, or by constructing an `Email` and calling `zonaiDB.sendEmail`.

If SMTP is misconfigured, check the server console for Courier warnings and verify the template file exists at the resolved path.

## See also

- **[sending-email.md](sending-email.md)** — provider setup, DNS (SPF/DKIM/DMARC), credentials, and deliverability
- **[config-and-env-flavors.md](config-and-env-flavors.md)** — flavors, env defines, and config worker compilation
- **[server-binding.md](server-binding.md)** — `baseUrl` for links in auth emails
- **[operations.md](operations.md#auth-collections)** — verify / magic-link / reset-password paths and expiry
- **[extensions.md](extensions.md)** — `email.send` helpers and default auth email hooks
- **[auth.md](auth.md)** — session tokens and auth endpoints
- **[rate-limiting.md](rate-limiting.md)** — limits on verify-email and other auth sends
