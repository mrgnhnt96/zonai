---
title: Production Delivery
description: Verifying a sending domain (SPF, DKIM, DMARC), proving credentials and DNS work, and testing where your mail actually lands.
---

[SMTP Setup](/email/smtp-setup) gets zonai talking to a provider. This page covers the rest: getting receiving servers to trust your domain, and checking each layer on its own so a failure is easy to trace.

## What you need

| | |
|---|---|
| A domain whose DNS you control | e.g. `example.com` |
| A transactional email provider | see [Choosing a provider](/email/smtp-setup#choosing-a-provider) |

You don't need email hosting or a mailbox to send. Receiving mail is a separate problem, and you only need to solve it if you want DMARC reports (see below).

## Verify the domain

Your provider gives you DNS records that prove you own the sending domain: usually an SPF `TXT`, a DKIM `TXT`, and a return-path `MX`. Resend, for example, puts SPF and the MX on a `send.` subdomain:

| Name | Type | Value |
|---|---|---|
| `send` | MX | `feedback-smtp.<region>.amazonses.com`, priority 10 |
| `send` | TXT | `v=spf1 include:amazonses.com ~all` |
| `resend._domainkey` | TXT | the long `p=…` key the provider generates |

Providers usually require all three records. The MX is where bounce and complaint feedback goes.

- **Only one SPF record is allowed per name.** If a name has two `v=spf1` records, both are ignored and SPF fails, so merge them into one. Putting SPF on a subdomain avoids clashing with whatever already owns the root SPF.
- **A subdomain MX does not conflict with your root MX in DNS.** Some registrar UIs block it anyway. Namecheap, for example, treats "Custom MX" and "Email Forwarding" as mutually exclusive for the whole domain. Switching to Custom MX deletes the forwarding records, so inbound mail to the bare domain stops.
- **Check that the save actually worked.** Some registrars need a confirmation on each row *and* a separate "save all". An unsaved row is dropped without a warning.
- **Watch out for the host field.** Many UIs add the domain to whatever you type. If the provider shows `send.example.com`, enter only `send`. Otherwise you create `send.example.com.example.com`, and verification fails with no hint why.

## Add DMARC yourself

Most providers verify a domain without DMARC. Add it anyway, because it's how you find out who else is sending as your domain:

```text
_dmarc   TXT   v=DMARC1; p=none; rua=mailto:dmarc@example.com; fo=1
```

Start at `p=none`, which only monitors. Read the aggregate reports for a couple of weeks, then move to `p=quarantine`, then `p=reject`. If you jump straight to `p=reject` before you know every legitimate sender, you can silently block your own mail.

The `rua` address has to accept reports. **It can't be a mailbox on another domain whose DNS you don't control.** A cross-domain `rua` needs an authorization record on the receiving domain. Most reporters skip sending without one, and they don't tell you. You have two options:

- Publish `v=DMARC1; p=none;` with no `rua`. The policy exists, but you get no reports.
- Keep a real mailbox (or a free forwarder) on the domain and point `rua` at it.

## Verify the credentials without sending

Before involving zonai, check that the credentials work with `openssl`. You complete `EHLO` and `AUTH` and quit before `MAIL FROM`, so this is safe to run against production credentials:

```bash
# port 465 (implicit TLS)
openssl s_client -connect smtp.resend.com:465 -quiet
# port 587 (STARTTLS)
openssl s_client -starttls smtp -connect smtp.resend.com:587 -quiet

# then type:
EHLO test
AUTH LOGIN
# answer the base64 prompts with base64 of the username, then the password
# "235 Authentication successful" = credentials good; QUIT before MAIL FROM
```

This tests the credentials and transport on their own. Once a failure is buried in app logs, a bad key, a wrong port/TLS pairing, an unverified domain and a bad recipient all look the same.

**This doesn't prove the domain is verified.** Providers generally accept `AUTH` from a valid key whatever the domain's state, and some accept `MAIL FROM` from an unverified domain and only reject the actual send. If this check passes and the real send is rejected, look at DNS, not the key.

## Confirm the defines reached the build

You can't inspect the compiled binary to check that `.env` values were baked in. `strings` doesn't reliably show Dart AOT string literals, and AOT builds aren't byte-reproducible, so a changed checksum proves nothing. Instead, watch the compile commands zonai runs:

```bash
( dart run zonai compile >/dev/null 2>&1 ) &
for i in $(seq 1 400); do ps -Ao args= | grep dart | grep -v grep >> /tmp/ps.txt; sleep 0.2; done
grep -o -- "-D[A-Z_]*=" /tmp/ps.txt | sort -u
```

Every key from your `.env`, including `SMTP_HOST`, should be listed.

## Test deliverability

Start with the cheapest check. Only the last two show you where mail actually lands.

**1. Check DNS against the authoritative nameserver.** A plain `dig` can answer from cache, so query the zone's own nameserver and include a control record:

```bash
NS=dns1.registrar-servers.com          # your zone's authoritative NS
dig @$NS +short A    example.com                      # CONTROL: zone is live
dig @$NS +short MX   send.example.com                 # return path
dig @$NS +short TXT  send.example.com                 # SPF
dig @$NS +short TXT  resend._domainkey.example.com     # DKIM
dig @$NS +short TXT  _dmarc.example.com                # DMARC
```

If the control returns an address and the rest return nothing, the records really aren't in the zone. Check that the registrar save went through, that the host field holds `send` and not `send.example.com`, and that you edited the right domain. Write one `dig` per line. In zsh, a loop like `for r in "TXT send.example.com"; do dig +short $r; done` passes the whole string as one argument, and every query comes back empty with exit code 0. Consider running this check on a schedule. The realistic failure is someone editing DNS a year from now.

**2. mail-tester.com.** Send one message through your app's real send path. You get a SpamAssassin score, SPF/DKIM/DMARC results and blacklist checks. Don't build a separate test message, because spam filters score the message you actually send.

**3. Real inboxes.** A score is not the same as inbox placement. Send to Gmail, Outlook, Yahoo and iCloud accounts and check where each message lands. In Gmail, **Show original** shows `SPF: PASS / DKIM: PASS / DMARC: PASS` directly.

**4. Google Postmaster Tools.** Set it up before you have volume. It only collects data from the day you add it.

**5. Provider events.** Watch your provider's bounce rate most closely. A new domain's reputation is fragile, and hard bounces damage it fastest.

## Content and recipients

- Plain transactional mail with no images, tracking pixel or unsubscribe link reads as legitimate. Emoji in the subject add some spam weight, so drop them if mail-tester flags them.
- **`$.email()` does not validate addresses.** It stores text exactly as `$.text()` does. Typos in user-entered addresses become hard bounces, so validate in `beforeCreate`. `beforeUpdate` receives the row as it was *before* the update is applied, so it can't check an incoming value. Validate updates on the client, or accept the gap. See [Update Hooks](/extensions/update-hooks).
