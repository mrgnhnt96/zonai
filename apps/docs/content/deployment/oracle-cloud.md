---
title: Deploying to Oracle Cloud
description: A worked deployment on Oracle Cloud's Always Free ARM VM — systemd, Caddy, runtime secrets and backups, for $0 a month.
---

A worked deployment on a plain Linux VM: one `zonai build` bundle under systemd, Caddy in front for
HTTPS, secrets injected at runtime, and a nightly SQLite backup. It runs on Oracle Cloud's
**Always Free** Ampere (ARM) VM, so a small app costs nothing to host.

This setup runs a production zonai app today. Only [step 1](#1-create-the-host) is specific to
Oracle. Any Ubuntu host with SSH and sudo works, `x64` or `arm64`.

It assumes you know what `zonai build` produces and what `--release` means. See
[Building for Production](/deployment/building-for-production),
[Cross-Compilation](/deployment/cross-compilation) and
[Running the Server](/deployment/running-the-server) first.

## Why a VM

- **One host, never two.** Zonai keeps everything in one SQLite file, so a second instance would
  mean a second database. Platforms that scale to zero or wipe the disk on restart (static hosting,
  serverless functions, scale-to-zero containers) can't run it.
- **It's free.** Oracle's Always Free tier includes Ampere A1 capacity (2 OCPUs and 12 GB of memory
  per tenancy, as of 2026-08-18), a persistent boot volume and generous outbound transfer. A zonai
  server and its workers use well under 100 MB of memory, so 1 OCPU and 6 GB is plenty. Check
  [Oracle's Always Free limits](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
  when you sign up. They have changed before.
- **It's ordinary Linux.** No image, no platform config: copy a directory, restart a service.
  Compare [Deploying to Fly.io](/deployment/fly-io) if you'd rather have a managed platform.

## What you end up with

```
 app ──HTTPS──▶ Caddy :443 ──▶ zonai serve --release  127.0.0.1:8080
                (auto TLS)       systemd: myapp.service
                                         │
                                         ▼
                                 /opt/myapp/.zonai/data/zonai.sqlite
                                         │
                                 myapp-backup.timer (daily) ──▶ /var/backups/myapp
```

zonai listens on localhost only. Caddy terminates TLS and gets its certificate from Let's Encrypt
by itself.

## 1. Create the host

Creating the account needs a person and a card. Always Free resources are never charged.

1. **Create an Oracle Cloud account.** Pick a home region with Ampere A1 capacity. You can't change
   it later.
2. **Upgrade the account to Pay As You Go.** It stays $0: Oracle doesn't charge for Always Free
   resources after the upgrade. Without it, Oracle reclaims Always Free VMs that look idle (low CPU,
   network and memory over a week), and an idle zonai server looks exactly like that. Set a budget
   alert at $1 to catch any mistake early.
3. **Create a compute instance:** image **Ubuntu 24.04**, shape **VM.Standard.A1.Flex** with 1 OCPU
   and 6 GB, and your SSH public key. Use no more than that, so a second app still fits in the free
   allowance. If a create fails with "Out of host capacity", try another
   availability domain, or try again later.
4. **Give it a reserved public IPv4.** A reserved IP outlives the instance, so your DNS name, and
   the URL your app ships with, survive rebuilding the host.
5. **Open ports 80 and 443** in the VCN's security list (ingress, TCP, from `0.0.0.0/0`). Caddy
   needs 80 for the certificate challenge. This is the cloud firewall. The host has its own,
   handled in [step 3](#3-prepare-the-host).

Keep each app in its own compartment, and give each app its own VM: separate hosts mean separate
deploys, reboots and blast radius. At 1 OCPU and 6 GB each, the free A1 allowance holds two.

Everything in this step can also be scripted with the OCI CLI. Make the script find each resource
by name before creating it, so it's safe to re-run. Give the script its own IAM user and group
rather than a key on your admin user, with a policy scoped to the app's compartment:

```
Allow group myapp-deployers to manage all-resources in compartment myapp
Allow group myapp-deployers to inspect compartments in tenancy
Allow group myapp-deployers to read objectstorage-namespaces in tenancy
```

Two OCI CLI behaviours that break naive scripts:

- A `list` with no results prints **nothing**, not an empty JSON array, so `jq '.data | length'`
  yields an empty string rather than `0`. Treat empty output as zero, or a "create if missing"
  check can silently skip the create.
- Until the API key file ends with the `OCI_API_KEY` label line the CLI asks for, it prints a
  warning to **stdout**, which breaks JSON parsing. Add the line, or the warning lands inside every
  result.

## 2. Build an `arm64` bundle

Cross-compile on your dev machine. Add `buildSettings` to the copy of the project you build from:

```yaml
# zonai.yaml
buildSettings:
  targetOs: linux
  targetArch: arm64
```

```bash
zonai build --flavor prod --release
file build/zonai   # ELF 64-bit LSB pie executable, ARM aarch64
```

Building from a scratch copy of the project keeps `buildSettings` out of the `zonai.yaml` you
develop with. `rsync` the project to a temporary directory, excluding `.zonai/data`, `build/`,
`.dart_tool/` and every `.env*`, then append the block above and build there.

Leave `JWT_SECRET`, `PASSWORD_SECRET` and any other secret out of the build's `.env.prod`. If one is
compiled in, `strings` on the binary recovers it. If none is, the server refuses to start until
the host supplies them, which is what you want. See
[Environment & Secrets](/deployment/environment-and-secrets).

To check, scan the bundle with `strings`, not `grep`: the executables are AOT-compiled, and a plain
`grep` doesn't reliably see inside them. Use a value you know is compiled in, such as your
`baseUrl`, as a positive control. If the scan can't find that, it can't find a secret either.

```bash
find build -type f -exec strings {} + | grep -c 'https://api.example.com'   # must be > 0
find build -type f -exec strings {} + | grep -c '<a secret value>'          # must be 0
```

## 3. Prepare the host

Run once as root on the VM. Every command is safe to re-run.

```bash
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl rsync sqlite3 libsqlite3-0 caddy

# The workers load libsqlite3.so, but Ubuntu ships only the versioned
# libsqlite3.so.0 unless you install the much larger -dev package.
lib="$(dpkg -L libsqlite3-0 | grep -m1 '/libsqlite3\.so\.0$')"
ln -sf "$lib" "$(dirname "$lib")/libsqlite3.so"

# A system user that owns the app and nothing else.
id myapp >/dev/null 2>&1 || useradd --system --home-dir /opt/myapp --shell /usr/sbin/nologin myapp
# The bundle is root's; the service can read it but only ever writes its data.
install -d -o root -g myapp -m 0750 /opt/myapp /opt/myapp/.zonai
install -d -o myapp -g myapp -m 0750 /opt/myapp/.zonai/data
install -d -o myapp -g myapp -m 0750 /var/backups/myapp
install -d -o root -g root -m 0700 /etc/myapp
```

**Secrets, generated once.** They live only on the host, in a root-only file the service reads at
start:

```bash
if [ ! -f /etc/myapp/secrets.env ]; then
  umask 077
  {
    echo "JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')"
    echo "PASSWORD_SECRET=$(openssl rand -base64 48 | tr -d '\n')"
  } > /etc/myapp/secrets.env
fi
chmod 0600 /etc/myapp/secrets.env
```

Never regenerate this file once users exist. **Losing `PASSWORD_SECRET` locks every user out**,
because it's mixed into every password hash. Keep a copy in a password manager. To rotate, see
[Rotating secrets](/deployment/environment-and-secrets#rotating-secrets).

**The host firewall.** Oracle's Ubuntu images ship iptables rules that drop everything except SSH,
on top of the security list from step 1:

```bash
for port in 80 443; do
  iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null ||
    iptables -I INPUT 5 -p tcp --dport "$port" -j ACCEPT
done
# Oracle's Ubuntu images ship netfilter-persistent; other images may not.
if command -v netfilter-persistent >/dev/null; then netfilter-persistent save; fi
```

## 4. The systemd unit

`/etc/systemd/system/myapp.service`:

```ini
[Unit]
Description=myapp server (zonai)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=myapp
Group=myapp
WorkingDirectory=/opt/myapp
# Root-only (0600). The bundle carries no secrets and refuses to start without these.
EnvironmentFile=/etc/myapp/secrets.env
ExecStart=/opt/myapp/zonai serve --release --host 127.0.0.1 --port 8080
Restart=on-failure
RestartSec=5
# zonai shuts down gracefully on SIGTERM; give in-flight requests time.
TimeoutStopSec=30

# Hardening: the server only ever writes its own data directory.
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/myapp/.zonai/data
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable myapp.service
```

## 5. Caddy

`/etc/caddy/Caddyfile`:

```
api.example.com {
	encode zstd gzip

	# The admin dashboard at /_ — see below.
	@admin path /_ /_/*
	respond @admin 404

	reverse_proxy 127.0.0.1:8080
}
```

```bash
systemctl reload caddy
```

Point an `A` record for the name at the reserved IP. If your DNS provider can proxy traffic, turn
that off for this record so Caddy can get its own certificate.

**No domain yet?** [sslip.io](https://sslip.io) names resolve to the IP they spell, so with a
reserved IP of `203.0.113.7`, `203-0-113-7.sslip.io` works as a real hostname, and Let's Encrypt
issues a certificate for it. List both names on the site line (`api.example.com,
203-0-113-7.sslip.io {`) while you move over, so nothing using the old one breaks.

Set `baseUrl` in your config to the public `https://` URL. Links in auth emails are built from it.
See [Server Binding](/deployment/server-binding#baseurl-vs-binding).

**Tell zonai it is behind a proxy.** Every request now reaches zonai from Caddy, so without this
the client address is always `127.0.0.1`. Every rate limit then becomes **one counter shared by
everyone**: a single abuser is never limited on their own, and one busy minute can lock every user
out of sign-up at once. Read the client address from `X-Forwarded-For`:

```dart in:app-config
trustedProxy: TrustedProxyConfig(
  headers: ['x-forwarded-for'],
  // useLeftmostIp: false, the default. Rightmost is the address Caddy added.
),
```

Caddy's `reverse_proxy` replaces a client-supplied `X-Forwarded-For` unless you configure
`trusted_proxies`, so the rightmost address is the real client and a spoofed header gets nowhere.
See [Trusted Proxies](/rate-limiting/trusted-proxies).

**The admin dashboard.** Every zonai server serves its admin UI at
[`/_`](/dashboard/overview). Its data needs an admin sign-in, but the page and its sign-in form are
public on any name that forwards `/_`. The Caddyfile above answers `/_` with a 404. Reach the
dashboard through an SSH tunnel instead:

```bash
ssh -L 8080:127.0.0.1:8080 ubuntu@203.0.113.7
# then open http://127.0.0.1:8080/_
```

Admin invite links open `/_/admin/invite?token=…` on `baseUrl`, so with `/_` blocked, an invited
admin accepts through the tunnel too. Drop the two `@admin` lines if you'd rather keep the
dashboard public.

**Tighten the auth rate limits.** Every auth route defaults to 100 requests per minute per IP. For
the routes that send email, that is enough for one IP to mail strangers in bulk and use up the
monthly Email Delivery allowance. Override them on the auth table, in its
[`AuthTableRateLimits`](/rate-limiting/auth-rate-limits):

```dart in:auth-rate-limits
@override
Future<RateLimitPolicy?> authenticatePolicy() async =>
    const RateLimitPolicy(maxRequests: 5, window: Duration(minutes: 15));

@override
Future<RateLimitPolicy?> sendResetPasswordPolicy() async =>
    const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));

@override
Future<RateLimitPolicy?> sendVerifyEmailPolicy() async =>
    const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));
```

OTP codes and magic links are sent through `POST /auth`, so `authenticatePolicy()` is the limit
that applies to them. `sendOtpPolicy()` and `confirmPolicy()` don't: `POST /auth/confirm`,
`POST /auth/upgrade` and `POST /auth/upgrade/confirm` each count against a per-IP counter shared
by all tables, at the framework default, and no table's override reaches them. A code itself
allows three wrong guesses before it is used up. See
[Auth Rate Limits](/rate-limiting/auth-rate-limits#endpoints-that-carry-no-table).

## 6. Deploy

From your dev machine, after [step 2](#2-build-an-arm64-bundle):

```bash
host=ubuntu@203.0.113.7

# Back up first (step 7). Then stop, swap the bundle in, and start, so the
# server and its workers always come from the same bundle. Never touch .zonai/data.
ssh "$host" 'sudo systemctl start myapp-backup.service && sudo systemctl stop myapp'
# -rlpt, not -a: without -o/-g, files rsync writes as root stay root-owned
# instead of taking your dev machine's uid. Nothing running as myapp can then
# replace its own executable or compiled rules. Only .zonai/data belongs to myapp.
rsync -rlpt --delete --exclude '.zonai/data' --rsync-path='sudo rsync' build/ "$host:/opt/myapp/"
ssh "$host" 'sudo systemctl start myapp'

# Only call it deployed once it answers through the public name.
curl -fsS https://api.example.com/health
```

The downtime is a few seconds. Pending migrations apply when the server opens the database, so a
new bundle with new migrations needs no separate step. See [Running the Server](/deployment/running-the-server#what-happens-at-startup).

A deploy script that does the above and then exercises a real request (sign in, read a row) catches
far more than `/health` does. Check `/health` against the public DNS name, not your local resolver,
so a stale local DNS cache can't fail a good deploy.

## 7. Backups

Only `zonai.sqlite` matters. It holds every account and every row. `zonai_log.sqlite` (the request
log) and `zonai_rate_limit.sqlite` (counters) are disposable, and a restored server recreates them
empty.

Copying the file while the server runs is not a backup: the database is in WAL mode, and a plain
copy can be torn. Use SQLite's online `.backup`, then check the result:

```bash
#!/usr/bin/env bash
# /usr/local/sbin/myapp-backup: one online, verified backup, keeping the newest 14.
# Outside /opt/myapp, so a deploy's rsync --delete can't remove it.
set -euo pipefail
db=/opt/myapp/.zonai/data/zonai.sqlite
dir=/var/backups/myapp
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$dir/.zonai-$stamp.sqlite"

sqlite3 "$db" ".backup '$tmp'"
if [ "$(sqlite3 "$tmp" 'PRAGMA integrity_check;')" != ok ]; then
  rm -f "$tmp" "$tmp-wal" "$tmp-shm"
  echo "backup: integrity_check failed" >&2
  exit 1
fi
out="$dir/zonai-$stamp.sqlite.gz"
gzip -9 -c "$tmp" > "$out"
rm -f "$tmp" "$tmp-wal" "$tmp-shm"
ls -1t "$dir"/zonai-*.sqlite.gz | tail -n +15 | xargs -r rm -f

# Off the host, when a write-only upload URL is configured (see below).
if [ -n "${BACKUP_UPLOAD_URL:-}" ]; then
  curl -fsS --retry 3 -X PUT --upload-file "$out" "${BACKUP_UPLOAD_URL%/}/$(basename "$out")"
fi
```

Install it with `install -m 0755 myapp-backup /usr/local/sbin/`, and run it daily with a timer, as
the `myapp` user:

```ini
# /etc/systemd/system/myapp-backup.service
[Unit]
Description=myapp database backup

[Service]
Type=oneshot
User=myapp
Group=myapp
# Optional, root-only: BACKUP_UPLOAD_URL=<the pre-authenticated request URL>
EnvironmentFile=-/etc/myapp/backup.env
ExecStart=/usr/local/sbin/myapp-backup
NoNewPrivileges=true
ProtectSystem=strict
# Reading a live WAL database writes its -shm index, so the data
# directory must be writable here too, not only the backup directory.
ReadWritePaths=/var/backups/myapp /opt/myapp/.zonai/data
```

```ini
# /etc/systemd/system/myapp-backup.timer
[Unit]
Description=Daily myapp database backup

[Timer]
OnCalendar=*-*-* 03:30:00 UTC
RandomizedDelaySec=15min
# A backup missed while the host was down runs at the next boot.
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl enable --now myapp-backup.timer
```

**Ship them off the host.** A backup on the same disk doesn't survive losing the host. Set this up
on day one, not after the first scare. Oracle's Always Free Object Storage works, and the host
never needs OCI credentials:

1. Create a **private** bucket in the app's compartment, and turn on **object versioning**.
2. Create a **pre-authenticated request** on the bucket with access type **"Permit object writes"**
   (AnyObjectWrite), and a long expiry, such as five years. Note its expiry.
3. Put the URL in `/etc/myapp/backup.env` (root, `0600`) as `BACKUP_UPLOAD_URL=...`. The backup
   script above uploads every verified backup to it.

The URL can only write. It can't list, read or delete. With versioning on, a leaked URL can't
destroy older backups either, because an overwrite keeps the previous version. To restore, download
the object in the console or with the OCI CLI from your own machine, then follow the steps below.
Renew the pre-authenticated request before it expires.

**Restore:** stop the service, keep the current database aside, unzip the backup over
`zonai.sqlite`, check it with `PRAGMA integrity_check`, and start the service again. Remove any
leftover `zonai.sqlite-wal` and `zonai.sqlite-shm` first. Practise it once before you need it.

## Email

Oracle Email Delivery has an Always Free allowance and speaks SMTP with STARTTLS on port 587. Set
up an email domain, an approved sender, and the SPF, DKIM and DMARC records it gives you. Then
create a user whose only permission is to send as that sender, and generate SMTP credentials for it.
Configure zonai as in [SMTP Setup](/email/smtp-setup).

Keep the SMTP credentials out of the bundle the same way as the signing secrets. Leave
`SMTP_USERNAME` and `SMTP_PASSWORD` out of the build's `.env.prod`, and add them to
`/etc/myapp/secrets.env` instead, which the unit already loads. Host, port and sender stay in
`.env.prod`. When `email` is configured, the server reads the two credentials from the process
environment at startup, and they win over anything compiled in. See
[Overriding a baked-in secret at runtime](/configuration/environment-variables#overriding-a-baked-in-secret-at-runtime).

**Where the links in auth emails point.** A reset or verification link is
`{baseUrl}{path}?s=<token>`, and the default paths, `/auth/reset-password` and `/auth/verify-email`,
are not pages zonai serves. Opened in a browser they fail. You serve those pages:

1. Override `resetPasswordConfig()` and `verifyEmailConfig()` in the table's operations to point at
   paths on your site. See [Auth Email Links](/operations/auth-operations#auth-email-links).
2. Each page reads `s` from its URL and posts it to `POST /auth/confirm`, as
   `{"type": "confirmResetPassword", "token": ..., "newPassword": ...}` or
   `{"type": "confirmVerifyEmail", "token": ...}`. See
   [Password Auth](/authentication/password-auth#password-reset).
3. If the pages live on your own domain, the same Caddy can serve them, and forward only
   `/auth/confirm` to zonai. The pages then stay same-origin, so a strict Content Security Policy
   holds and the API needs no CORS.

## Checklist

- [ ] Account upgraded to Pay As You Go, with a $1 budget alert
- [ ] Reserved IP, and ports 80/443 open in both the security list and iptables
- [ ] Bundle built for `linux`/`arm64`; `file build/zonai` says aarch64
- [ ] No secret in the build's `.env.prod`; secrets in a root-only `EnvironmentFile`
- [ ] A copy of `PASSWORD_SECRET` somewhere safe
- [ ] `baseUrl` is the public `https://` URL, and the reset and verify links open pages you serve
- [ ] `trustedProxy` reads `x-forwarded-for`, so rate limits count each client separately
- [ ] `/_` is blocked at Caddy, or you've decided to keep the dashboard public
- [ ] Auth rate limits tightened for the routes that send email
- [ ] `https://<your name>/health` answers through public DNS
- [ ] The backup timer is enabled, one backup has been restored as a test, and backups reach a
      versioned bucket
- [ ] Rebooted once, and the service, Caddy and the timer all came back
