# Sending email in production

**[email.md](email.md)** covers the in-app half of email: `EmailConfig`, Mustache templates, and how a send happens. This page is the operational half — provider, DNS, credentials, transport, and how to prove any of it actually works — for getting a zonai app sending real mail through a real SMTP provider.

## What has to be true

Three separate things have to hold, and they fail independently:

1. **Credentials reach the compiled worker.** Compile-time, via `.env`.
2. **The transport settings agree with each other.** Port and TLS mode are one decision in two variables.
3. **The receiving world trusts the domain.** SPF, DKIM, DMARC — DNS, nothing to do with the app.

Most "email doesn't work" is #1 or #2. Most "email works but lands in spam" is #3.

## Prerequisites

| | |
|---|---|
| A domain you control DNS for | e.g. `example.com` |
| A transactional email provider | see below |
| The zonai CLI, in your app directory | |

You do not need email hosting, a mailbox, or a mail server. Sending is a relay; receiving is a separate, also-free problem. Conflating them is what makes this look expensive.

## Step 1 — Choose a provider

| Provider | Free tier | Notes |
|---|---|---|
| **Resend** | 3,000/mo, 100/day, 1 domain | SMTP relay on all plans; the examples below use it. |
| Brevo | 300/day (~9,000/mo) | More daily headroom; counts To+CC+BCC separately. |
| Amazon SES | $0.10/1,000 | Cheapest at scale; sandboxed until you request production access (1–3 business days). |
| ~~SendGrid~~ | none | Free plan retired May 2025. Not an option. |

A low-volume free tier is enough to get started; switching providers later is a credential change, not a code change.

## Step 2 — Verify the domain

Providers issue DNS records to prove you own the sending domain — typically an SPF `TXT` record, a DKIM `TXT` record, and a return-path `MX`. Resend, for example, puts its SPF on a `send.` subdomain rather than the root:

| Name | Type | Value |
|---|---|---|
| `send` | MX | `feedback-smtp.<region>.amazonses.com`, priority 10 |
| `send` | TXT | `v=spf1 include:amazonses.com ~all` |
| `resend._domainkey` | TXT | the long `p=…` key the provider generates |

**Only one SPF `TXT` record is legal per name.** If you put a second `v=spf1` record on the same host, both are ignored and SPF fails — records must be merged into one. Putting SPF on a subdomain sidesteps this by not competing with whatever already owns the root SPF; not every provider does this.

All three records are typically required to verify — DKIM, SPF, *and* the MX. The MX is the return path for bounce and complaint feedback.

Alignment tends to work out without extra effort: DKIM signs as `d=example.com`, and a `send.example.com` return-path is relaxed-aligned with a `From:` of `alerts@example.com`, so DMARC passes on both legs.

### There is no DNS-level conflict — but your registrar may invent one

`send.example.com` MX and `example.com` MX are independent records; putting the provider's MX on a subdomain is precisely what lets it coexist with whatever already receives your mail. At the DNS layer, nothing collides.

**Your registrar's UI may make it collide anyway.** On Namecheap, for example, the Advanced DNS page exposes a single per-domain **Mail Settings** dropdown, and `Custom MX` and `Email Forwarding` are mutually exclusive modes — you cannot add *any* MX record, even on a subdomain, while Email Forwarding is selected, and selecting Custom MX deletes the forwarding MX records along with the root SPF that came with them. If you hit this shape:

1. Switch to Custom MX first. This is destructive: inbound mail to the bare domain stops immediately.
2. Add the provider's MX and TXT records.
3. Save — and check that the save actually took. Some registrars require a per-row confirmation *and* a separate "save all" press; an unsaved row is discarded silently with no warning, and a missing record after a save is the first thing to check.

> **The paste gotcha.** Some UIs append the domain to whatever you type in the Host field. If the provider displays the full `send.example.com`, paste only `send` — pasting the full value creates `send.example.com.example.com`, which resolves for nobody and fails verification with no clue why.

If you need inbound mail back afterwards under a mode like Custom MX, add a forwarding provider that works there (a free tier such as ImprovMX is two MX records on `@`) rather than switching Mail Settings back, which deletes the provider's MX again.

## Step 3 — Add DMARC yourself

Most providers verify a domain without DMARC. Add it anyway — it is how you find out who else is sending as your domain:

```text
_dmarc   TXT   v=DMARC1; p=none; rua=mailto:dmarc@example.com; fo=1
```

Start at `p=none` (monitor, change nothing). Read the aggregate reports for a couple of weeks, then move to `p=quarantine`, then `p=reject`. Going straight to `p=reject` before you know every legitimate sender is how you silently blackhole your own mail.

`rua=` needs to actually arrive somewhere, and **you cannot simply point it at a mailbox on a different domain you don't control DNS for.** When the `rua` address is on a different domain than the DMARC record, the receiving domain must publish an authorization record proving it consents to receive reports for your domain (`example.com._report._dmarc.gmail.com` for a Gmail address, which you cannot add to `gmail.com`). Most reporters will refuse to send anything, and the failure is completely silent.

Two honest options:

- **`v=DMARC1; p=none;` with no `rua`.** The policy is published, you just get no feedback loop. Correct when you have no inbound mail on the domain.
- **Keep a real mailbox on the domain** and use `rua=mailto:dmarc@example.com`. Free inbound forwarding is usually enough.

## Step 4 — Put the credentials in `.env`

Zonai reads a flavor-specific `.env` file from your app root and turns every key into a compile-time `-D` define on each worker. See **[config-and-env-flavors.md](config-and-env-flavors.md#environment-files)** for the full mechanism — which file is loaded per `--flavor`, the file format, and which workers receive the defines. Two things worth restating here because they bite specifically on SMTP credentials:

- **There is no fallback between env files.** `--flavor prod` loads `.env.prod` only; if it's missing, zonai compiles with *no* env defines at all, even if a plain `.env` exists. A missing `SMTP_HOST` then silently takes its `defaultValue` (or an empty string) rather than falling back to a different file.
- **There is no `--dart-define-from-file` flag** — see **[config-and-env-flavors.md](config-and-env-flavors.md#there-is-no---dart-define-from-file)**. The `.env` file is the only mechanism; an invented flag is silently dropped and the build succeeds with zero defines injected.

```env
# apps/server/.env — gitignored, never committed
SMTP_HOST=smtp.resend.com
SMTP_PORT=465
SMTP_SSL=true
SMTP_USERNAME=resend
SMTP_PASSWORD=re_…
SMTP_FROM_ADDRESS=alerts@example.com
SMTP_FROM_NAME=Example Alerts
```

Read these back with `String.fromEnvironment` in your config worker's `EmailConfig` — see **[config-and-env-flavors.md#using-env-in-config-example](config-and-env-flavors.md#using-env-in-config-example)** for a worked example.

**Defaults are silent.** A missing key yields `defaultValue` and nothing warns. For a provider like Resend, `SMTP_USERNAME` is the literal string `resend`, not your email address — a plausible-looking wrong value fails at AUTH, not at build.

### Gate the feature on the credential

```dart no-analyze
// Sketch — `recipientEmail` and `smtpHost` stand in for your own variables.
if (recipientEmail != null && smtpHost.isNotEmpty) { /* ... */ }
```

An empty `EmailConfig.host` (or an unset `AppConfig.email`) makes the whole channel a no-op, which is what lets email-sending code ship and sit inert until credentials exist. Keep the `.env` block commented out as a unit until the key is real — a host set without a working password turns a silent no-op into a failing send.

### Compile-time vs runtime

| | Set where | Read how |
|---|---|---|
| **Compile-time** | `.env` at build | `String.fromEnvironment` in config, rules, extensions, operations, rate-limit Dart |
| **Runtime** | your host's own secret store | `Platform.environment` in your own processes, outside zonai's compiled workers |

SMTP credentials are compile-time. Setting a runtime secret on your host does nothing for them — the worker never reads the process environment. The compiled worker executables contain your secrets; treat `.zonai/executables/` and `build/` as sensitive.

## Step 5 — Make the port and TLS mode agree

The single most likely thing to cost you an afternoon.

Zonai's `EmailConfig.ssl` maps directly to `package:mailer`'s `SmtpServer(ssl: ...)` (`apps/zonai/lib/src/email/courier.dart:52-58`), which treats `ssl` as **implicit** TLS: `ssl: true` opens the socket with `SecureSocket.connect` (`mailer 7.1.0, src/smtp/connection.dart:133`); `ssl: false` opens a plain `Socket` and upgrades via STARTTLS if the server's EHLO advertises it (`src/smtp/smtp_client.dart:24-41`).

The two standard submission ports want **opposite** settings:

| Port | Greeting | `ssl:` | |
|---|---|---|---|
| 465 | TLS handshake | `true` | implicit TLS |
| 587 | plaintext, then STARTTLS | `false` | still encrypted in transit |
| 465 | | `false` | ✗ |
| 587 | | `true` | ✗ |

`ssl: false` is **not** "unencrypted" — it is STARTTLS, and every provider worth using advertises it.

A mismatch does not degrade gracefully: `ssl: true` against 587 blocks in a TLS handshake the server never starts, surfacing as a connection timeout that names nothing about TLS. Both values look individually reasonable, which is exactly why a guard that states the invariant is worth writing — so the failure names itself:

```dart in:smtp-guard
String? smtpTransportMismatch(EmailConfig config) {
  if (config.port == 465 && !config.ssl) {
    return 'port 465 expects implicit TLS (ssl: true)';
  }
  if (config.port == 587 && config.ssl) {
    return 'port 587 expects STARTTLS (ssl: false)';
  }
  return null; // non-standard ports (2465/2587) deliberately left alone
}
```

Call it in your config worker's `main()` and throw if it returns non-null, so a bad `.env` value fails at compile time instead of as an unexplained timeout in production.

## Step 6 — Verify the defines actually landed

**`strings` on a compiled worker does not tell you.** Dart AOT snapshots do not expose app string literals to `strings` or `grep` the way source does — a hostname or a `defaultValue` literal generally will not appear in the compiled executable, while data pulled in from other packages (ICU tables, etc.) may. Absence there means nothing.

**Comparing checksums does not tell you either.** Dart AOT builds are not guaranteed byte-reproducible — recompiling twice from an identical `.env` can produce different binaries. "The binary changed, so the define landed" is not a valid inference.

What does work is observing the compile itself — watch the `dart compile exe` invocations zonai shells out to and grep their argument list for your keys:

```bash
( dart run zonai compile >/dev/null 2>&1 ) &
for i in $(seq 1 400); do ps -Ao args= | grep dart | grep -v grep >> /tmp/ps.txt; sleep 0.2; done
grep -o -- "-D[A-Z_]*=" /tmp/ps.txt | sort -u
```

which should list every key from your `.env`, `SMTP_HOST` included.

### Verify the credentials without sending

Before wiring anything into zonai, confirm the credentials work at all with a plain `openssl` probe that completes `EHLO` and `AUTH LOGIN` and quits — never issuing `MAIL FROM`/`RCPT TO`/`DATA`, so it is safe against production credentials at any time:

```bash
# port 465 (implicit TLS)
openssl s_client -connect smtp.resend.com:465 -quiet
# port 587 (STARTTLS)
openssl s_client -starttls smtp -connect smtp.resend.com:587 -quiet

# after the handshake, type by hand:
EHLO test
AUTH LOGIN
# the server replies with base64 prompts; answer with base64 of the username, then the password
# "235 Authentication successful" confirms the credentials; QUIT before typing MAIL FROM
```

This isolates the credential-and-transport layer from everything else. A failing send has several independent causes — bad key, wrong port/TLS pairing, unverified domain, bad recipient — and once the failure is buried in an app's own delivery logging they are indistinguishable.

**It does not prove the domain is verified.** Providers generally accept `AUTH` from a valid key regardless of domain state, and some (Resend included) answer `250 Accepted` to `MAIL FROM` on an unverified domain, deferring that check to the actual send. Green here plus a rejected send means look at DNS, not the key.

Beyond that, a real send is the only proof — everything before it is inference.

## Step 7 — Test deliverability

Cheapest rung first. Rungs 1–2 are prerequisites; rung 3 is the only ground truth.

**1. Assert the DNS.** Deterministic, instant, free, and the only rung worth automating.

Query the authoritative nameserver, not your resolver, and always run a control — a plain `dig` answers from cache, so a missing record and a stale cache look identical:

```bash
NS=dns1.registrar-servers.com          # your zone's authoritative NS
dig @$NS +short A    example.com                      # CONTROL: zone is live
dig @$NS +short MX   send.example.com                 # return path
dig @$NS +short TXT  send.example.com                 # SPF
dig @$NS +short TXT  resend._domainkey.example.com     # DKIM
dig @$NS +short TXT  _dmarc.example.com                # DMARC
```

The control line is what makes a negative result meaningful. If the control returns an address and the rest return nothing, the records genuinely are not in the zone — not cached, not propagating, not saved.

When they are all empty, check in this order: (1) your own query is well-formed (see below), (2) the registrar's save committed, (3) the Host field holds `send`, not `send.example.com`, (4) you edited the zone for the right domain.

> **Do not loop over record types in zsh.** zsh — unlike bash — does not word-split unquoted parameter expansions, so a natural-looking loop like
>
> ```zsh
> for r in "TXT send.example.com" "MX send.example.com"; do set -- $r; dig +short $1 $2; done
> ```
>
> passes `"TXT send.example.com"` to `dig` as a single argument. `dig` returns empty for every record, exit code 0, no error — indistinguishable from the records not existing. Write the queries out literally, one `dig` per line, or quote-split explicitly with `${=r}`. A verification loop that fails silently is worse than no loop, because its output is trusted.

Worth a scheduled check rather than a one-time one: the realistic failure is someone editing DNS a year from now, DKIM silently ceasing to resolve, and nobody finding out until a customer says they never got the mail.

**2. mail-tester.com.** Send one real message through your app's actual send path and get a SpamAssassin score plus SPF/DKIM/DMARC verdicts and blacklist checks. Free tier is 3 tests per 24h.

Send through your app's real send function, not a hand-built message down a parallel path — a test that builds its own message proves nothing about the one that ships, and spam filters score the message you actually send.

**3. Real seed inboxes — the actual test.** A score is not placement. Send to Gmail, Outlook/Hotmail, Yahoo, and iCloud accounts and look at where each one lands. In Gmail, **Show original** prints `SPF: PASS / DKIM: PASS / DMARC: PASS` explicitly; that is confirmation, a third-party score is not.

**4. Google Postmaster Tools.** Set it up before you have volume — it only shows data going forward, and it is the only domain reputation signal Google gives you directly.

**5. Provider events.** Your provider's delivered/bounced/complained stream. Watch bounce rate hardest: a new domain's reputation is fragile and hard bounces damage it fastest.

### Content notes

Plain-text, no images, no tracking pixel, no unsubscribe link reads as legitimate transactional mail — which is what most zonai-sent auth and alert email is. Two things to keep an eye on:

- **Emoji in the subject line** carry some spam weight. Drop it if mail-tester flags it.
- **Recipient validation.** If the address comes from user input, typos become hard bounces and hard bounces cost reputation. Two zonai specifics matter here:

  **`$.email()` does not validate.** `EmailTransformer.encode`/`decode` return their input unchanged, and `sqlType` is `TEXT` — byte-identical to `$.text()` (`libs/zonai_schema/lib/src/column_types/email_column.dart:8,18,21`). Its only real consumer locates the login-identity column on auth tables by transformer type. Choosing it over `$.text()` buys a schema-shape hint for the admin UI and nothing else — it is not the place to put a correctness guarantee.

  **Validate in `beforeCreate`, and know the update path can't be covered the same way.** `Extension.beforeUpdate` receives the row **as read fresh from the database, before the caller's submitted updates are applied** (`libs/zonai_schema/lib/src/extension.dart:34-36`; see **[extensions.md](extensions.md#hook-methods)**), so a check there validates the stale value, not the incoming one. No hook sees the proposed replacement before it commits — `afterUpdateSuccess` gets both `before` and `after`, but only once the row is already written. Update-time validation of a mutated field has to be enforced client-side (or accepted as a gap); that asymmetry is worth a comment wherever you rely on it, since it reads like an oversight otherwise.

## See also

- **[email.md](email.md)** — `EmailConfig`, Mustache templates, and how a send happens in zonai
- **[config-and-env-flavors.md](config-and-env-flavors.md)** — flavors, `.env` resolution, and compile-time defines
- **[extensions.md](extensions.md)** — hook order and the `beforeUpdate` stale-row shape
- **[server-binding.md](server-binding.md)** — `AppConfig.baseUrl` for links in auth emails
