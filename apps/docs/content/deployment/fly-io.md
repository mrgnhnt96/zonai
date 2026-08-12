---
title: Deploying to Fly.io
description: A worked Fly.io deployment — cross-compiled bundle, persistent volume, and first-boot bootstrap.
---

This is the deployment we actually run, in the order we run it: cross-compile the bundle on your dev
machine, package it into a minimal image, bootstrap the database on the app machine, and confirm it's
serving. Written so you can follow it for a different app.

It assumes you already know what `zonai build` produces and what `--release` means — see
[Building for Production](/deployment/building-for-production), [Cross-Compilation](/deployment/cross-compilation),
and [Running the Server](/deployment/running-the-server) first.

Written against zonai 0.6.2. Project-linked builds (in-process ops/rules) landed in 0.6.1, and 0.6.2
is the first version whose cross-compiled bundle is target-arch all the way through — on 0.6.1 the two
`.aot` snapshots come out for the build host. See [step 3](#3-build-the-deploy-bundle).

## Do You Even Need Docker?

You need a Dockerfile — Fly builds an image — but you do **not** need Docker installed locally, and
nothing gets compiled inside the image. `zonai build` cross-compiles a Linux bundle directly on your
Mac, and the Dockerfile just copies it in. Fly's remote builder assembles the image.

The one case that needs a real Linux container is rebuilding the **zonai CLI itself** from source —
see [Rebuilding the framework from source](#appendix-rebuilding-the-framework-from-source) at the
bottom. If your installed `zonai` already builds and serves your app, skip it.

## What You End Up With

One Fly machine, with a persistent volume for the SQLite database. If your app has a second,
public-facing Dart process (a proxy, a webhook receiver, a Jaspr front end), it looks like this:

```
                    ┌─────────────────────────────────────────┐
  internet  ──443──▶│ public process        :8080             │
                    │   proxy + webhooks                      │
                    │        │                                │
                    │        └─▶ zonai serve  127.0.0.1:8081  │
                    │                  │                      │
                    │                  ▼                      │
                    │        /app/.zonai/data ◀── Fly volume  │
                    └─────────────────────────────────────────┘
```

If zonai is the only process, it's simpler: bind `zonai serve` to `0.0.0.0` on the port `fly.toml`
exposes, and skip the second binary and the sequencing in [step 7](#7-start-script). Each step notes
where that applies.

Two properties to be aware of before you start:

- **One machine, not more.** Zonai stores everything in a SQLite file. Multiple `zonai serve`
  instances sharing one database file isn't supported, so this is a single-node deployment by
  construction.
- **You need a volume.** Without one, every deploy and every restart starts from an empty database.

## Prerequisites

| Requirement | Notes |
|---|---|
| `zonai` binary | in your app directory (e.g. `apps/server/zonai`) |
| Dart SDK | on the build machine |
| `flyctl` | installed and authenticated (`fly auth login`) |
| Docker | **not needed locally** — Fly's remote builder handles it |

You do not need a container or an emulator to produce Linux binaries. Zonai cross-compiles directly,
so an Apple Silicon Mac can build a `linux/x64` bundle natively.

## 1. Tell Zonai What to Build For

In `zonai.yaml`, next to your existing paths:

```yaml
version: 0.6.2

migrationsPath: .zonai/migrations
schemasPath: lib/src/schemas
rulesPath: lib/src/rules
operationsPath: lib/src/operations
extensionsPath: lib/src/extensions
configPath: lib/src/config

# Fly machines run linux/x64.
buildSettings:
  targetOs: linux
  targetArch: x64
```

`buildSettings` is what turns `zonai build` into a cross-compile — see
[Cross-Compilation](/deployment/cross-compilation). Keep `version` matching the binary you're
actually running.

## 2. Put Compile-Time Config in `.env`

Zonai reads a `.env` from your **app root** — the same directory as `zonai.yaml` — and bakes every
key into the compiled workers as a `-D` define. Your config reads them back with
`String.fromEnvironment`:

```dart
// lib/src/config/db_config.dart
AppConfig main() => AppConfig(
  appName: 'MyApp',
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET', defaultValue: 'dev-password-secret'),
  jwtSecret: const String.fromEnvironment('JWT_SECRET', defaultValue: 'dev-jwt-secret'),
  baseUrl: const String.fromEnvironment('BASE_URL', defaultValue: 'http://localhost:8080'),
);
```

```sh
# apps/server/.env   — gitignored, never committed
JWT_SECRET=...
PASSWORD_SECRET=...
BASE_URL=https://your-app.fly.dev
```

Three things worth knowing:

- **No `--flavor` means plain `.env`.** With `--flavor prod`, zonai reads `.env.prod` **only** — it
  does not fall back to `.env`. If `.env.prod` is missing you get a warning
  (`No flavor-specific .env file found for flavor: prod`) and **no defines at all**, so every
  `String.fromEnvironment` silently takes its `defaultValue`.
- **Defaults are silent.** A missing key is never an error. Verify after building — see
  [step 3](#3-build-the-deploy-bundle).
- **The compiled artifacts contain your secrets.** They're baked in, not read at runtime. Treat
  `build/` as sensitive and don't publish the image anywhere public. See
  [Environment & Secrets](/deployment/environment-and-secrets).

You can also pass keys on the command line instead of (or in addition to) `.env`, with
`--dart-define KEY=VALUE`. Note the space — `--dart-define=KEY=VALUE` fails to parse, because
argument splitting happens on every `=`. CLI defines win over matching `.env` keys.

### Compile-Time vs Runtime Config

Two different mechanisms, easy to conflate:

| Kind | Where it's set | Where it's read | Example |
|---|---|---|---|
| **Compile-time** | `.env` at build | `String.fromEnvironment` | `JWT_SECRET` |
| **Runtime** | `fly secrets set` | `Platform.environment` | webhook secrets |

Anything your *own* Dart process reads at startup belongs in Fly secrets ([step 9](#9-create-the-app-volume-and-secrets)).
Anything zonai's config worker needs belongs in `.env` at build time.

## 3. Build the Deploy Bundle

One script produces everything the image needs. Nothing is compiled inside Docker.

```sh
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> Building apps/server (zonai build --release)"
(cd apps/server && ./zonai build --release)

# Only if you have a second, public-facing process:
mkdir -p apps/gateway/build
(cd apps/gateway && dart pub get && dart compile exe \
  --target-os linux --target-arch x64 \
  bin/gateway.dart -o build/gateway)

# Nothing host-arch may reach the image. A wrong-arch artifact builds and
# deploys without complaint and only fails at runtime, so check here.
bad=0
while IFS= read -r artifact; do
  desc="$(file -b "$artifact")"
  case "$desc" in
    *ELF*|*Mach-O*|*PE32*)
      if [[ "$desc" != *x86-64* ]]; then
        echo "ERROR: $artifact is not x86-64: $desc" >&2
        bad=1
      fi
      ;;
  esac
done < <(find apps/server/build apps/gateway/build -type f)
[[ "$bad" -eq 0 ]] || { echo "Bundle has non-linux/x64 binaries." >&2; exit 1; }
```

You should get `apps/server/build/` containing `zonai`, `.zonai/executables/`, `.zonai/lib/`,
`.zonai/migrations/`, plus your second binary if you have one.

**Verify before deploying.** Two checks worth running the first time:

```sh
# Everything linux/x64?
find apps/server/build -type f -exec file {} \; | grep -v "x86-64" | grep -iE "ELF|Mach-O"
# (no output = good)

# Did your .env actually get baked in?
strings apps/server/build/.zonai/executables/db_config.exe | grep -c 'dev-jwt-secret'
# 0 = your real secret was used; 1 = it fell back to the default
```

Every object file in the bundle should be `x86-64`, including the two `.aot` snapshots in
`.zonai/executables/`. Before 0.6.2 they came out for the build host — `zonai build` passed
`buildSettings` to the `.exe` compile and not to the aot-snapshot one — and a bundle carrying them
deployed and served without complaint, so it's worth keeping this check in your script rather than
trusting the build.

## 4. Dockerfile

The image compiles nothing. It installs the runtime libraries and copies the prebuilt bundle in.

```dockerfile
FROM debian:bookworm-slim

# libsqlite3-0 because the compiled workers link against libsqlite3.
# Debian ships only the versioned libsqlite3.so.0, not the unversioned
# libsqlite3.so that FFI loaders look for — hence the symlink. That symlink
# otherwise only comes from the much heavier -dev package.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 \
              /usr/lib/x86_64-linux-gnu/libsqlite3.so

WORKDIR /app

COPY apps/server/build/ .
COPY apps/gateway/build/gateway ./gateway
COPY apps/server/scripts/ ./scripts/

RUN chmod +x ./zonai ./gateway ./scripts/start.sh ./scripts/ensure_admin.sh

EXPOSE 8080

CMD ["./scripts/start.sh"]
```

`curl` is there because `start.sh` uses it to wait for zonai's health endpoint. Drop it if you don't.

If zonai is your only process, you don't need the scripts at all — `CMD ["./zonai", "serve", "--release", "--host", "0.0.0.0"]`
plus a `release`-safe bootstrap is enough (but read [step 6](#6-bootstrap-script) before reaching for
`release_command`).

## 5. `.dockerignore`

The build context only needs the build outputs and the scripts. Without this, Fly spends minutes
tarring and uploading your entire repo — including every `.git`.

```
*
!Dockerfile
!apps/
!apps/server/
!apps/server/build/
!apps/server/build/**
!apps/server/scripts/
!apps/server/scripts/**
!apps/gateway/
!apps/gateway/build/
!apps/gateway/build/gateway
```

Note the pattern: deny everything, then re-include. **Every ancestor directory of a kept path needs
its own `!` line** — once a parent is excluded, a deeper negation alone won't reliably pull it back in.

## 6. Bootstrap Script

Migrations and any first-run seeding go in their own script. This one also creates the admin account
a gateway process signs in as; skip that half if you don't need one.

```sh
#!/bin/sh
set -eu

./zonai db migrate apply

if ./zonai db admin list | grep -Fq "email: ${ADMIN_EMAIL}"; then
  echo "Admin account for ${ADMIN_EMAIL} already exists, skipping."
else
  # --no-verify: no SMTP configured, so the verification email has nowhere to go
  ./zonai db admin add -e "${ADMIN_EMAIL}" -p "${ADMIN_PASSWORD}" --no-verify
fi
```

Four things this ordering depends on:

- **Migrations first.** `zonai serve` auto-applies pending migrations, but that's too late here:
  `db admin` touches a table a migration creates, so on a fresh volume it fails unless migrations
  have already been applied.
- **Check-then-add, not add.** `db admin add` errors on a duplicate email and returns a non-zero
  exit code, which under `set -e` kills the boot. Checking first makes the script safe to run on
  every boot.
- **Match the `list` output loosely.** `db admin list` indents each field (`  email: you@example.com`),
  so `grep -Fqx "email: ..."` never matches and you'd re-add on every boot. Plain `grep -Fq` on the
  substring is what works.
- **No server needed.** Both commands work against the database file directly, which is why this can
  run before `zonai serve` starts.

<Warning>

**Run this from your start script, not a Fly `release_command`.** Release-command machines get the
network, env and secrets but **no volumes** — per Fly's config reference: *"It has no volumes
attached, and the Machine is destroyed after the command completes."* Anything written to your data
directory from one is discarded, silently, after reporting success. Since both commands above write
to the data directory, they have to run on the app machine.

</Warning>

## 7. Start Script

Sequences everything on boot. This is the image's `CMD`.

```sh
#!/usr/bin/env bash
set -euo pipefail

ZONAI_PORT="${ZONAI_INTERNAL_PORT:-8081}"

# Runs here, on the app machine, because this is where the volume is mounted.
./scripts/ensure_admin.sh

./zonai serve --release --host 127.0.0.1 --port "$ZONAI_PORT" &
ZONAI_PID=$!
trap 'kill -TERM "$ZONAI_PID" 2>/dev/null || true' TERM INT

# Wait for zonai to actually answer before starting the public process,
# which signs in at startup and would fail against a half-booted server.
until curl -fs "http://127.0.0.1:${ZONAI_PORT}/health" >/dev/null 2>&1; do
  sleep 0.5
done

export ZONAI_BASE_URL="http://127.0.0.1:${ZONAI_PORT}"
exec ./gateway
```

Points that matter:

- `--release` on `zonai serve` disables file watching and recompiling. Always use it in production;
  `build --release` must have run first.
- `zonai serve` binds to **127.0.0.1** so it is never publicly reachable. The front-end process is
  the only thing on a public port. See [Server Binding](/deployment/server-binding).
- The health poll hits zonai's own built-in `GET /health`. Your public process's health path is
  whatever you gave it — the two are different endpoints on different ports.
- `exec` on the last process makes it PID 1, so Fly's signals reach it.

**If you have no front-end process:** drop the poll and run zonai in the foreground bound to the
public port — `exec ./zonai serve --release --host 0.0.0.0 --port 8080`.

## 8. `fly.toml`

```toml
app = "myapp-server"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

# No [deploy] release_command — see step 6.

[env]
  ZONAI_INTERNAL_PORT = "8081"

# Required. The SQLite database lives here; without a volume every deploy
# and restart starts from an empty database.
[[mounts]]
  source = "myapp_data"
  destination = "/app/.zonai/data"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1

  [[http_service.checks]]
    grace_period = "15s"
    interval = "15s"
    method = "GET"
    path = "/healthz"
    timeout = "5s"

[[vm]]
  size = "shared-cpu-1x"
  memory = "512mb"
```

`internal_port` must match whatever your public process listens on, and the check's `path` must be an
endpoint *that* process serves (`/healthz` here). If zonai is the public process, use its built-in
`/health` instead.

The volume `destination` must match zonai's data directory — `/app/.zonai/data` when `WORKDIR` is
`/app`, since the database lives at `.zonai/data` relative to the app directory.

`auto_stop_machines = false` with `min_machines_running = 1` keeps the single machine up. If you'd
rather scale to zero, be aware every cold start re-runs the bootstrap script.

## 9. Create the App, Volume, and Secrets

The volume must exist before the first deploy:

```sh
fly apps create myapp-server

fly volumes create myapp_data --app myapp-server --region iad --size 1

fly secrets set --app myapp-server \
  ADMIN_EMAIL="admin@example.com" \
  ADMIN_PASSWORD="<generate a strong one>" \
  STRIPE_WEBHOOK_SECRET="<from your provider's dashboard>"
```

The volume's `--region` must match `primary_region`, and its name must match `[[mounts]] source`.
Size is in GB.

These secrets are the **runtime** ones from [step 2's table](#compile-time-vs-runtime-config) — read
by your own process via `Platform.environment`. Zonai's own config secrets went in at build time via
`.env`.

## 10. Deploy and Verify

```sh
./scripts/build_deploy_bundle.sh   # rebuild the artifacts
fly deploy
```

`fly deploy` with no flags uses Fly's remote builder, which is what you want: the bundle is already
`linux/x64` and the image must be too. Avoid `--local-only` on Apple Silicon — it builds an `arm64`
image around `x64` binaries, which only fails once the machine boots. If you do want to build
locally, build the image explicitly with `--platform linux/amd64` first (see
[Verifying locally](#verifying-locally-optional)).

Then confirm it's actually running:

```sh
fly status

PROCESS │ ID             │ VERSION │ REGION │ STATE   │ CHECKS
app     │ 8e2579c7724398 │ 3       │ iad    │ started │ 1 total, 1 passing
```

<Warning>

**Check for `started`, not just a successful deploy.** If the machine previously exhausted its
restart budget, Fly updates the config, reports the deploy as successful, and leaves the machine
`stopped`. Start it explicitly with `fly machine start <machine-id>`.

</Warning>

Boot logs should look like this on a fresh volume:

```
Applied pending SQL migrations
Admin created successfully
Serving at http://127.0.0.1:8081/
gateway listening on :8080, proxying to http://127.0.0.1:8081
Health check 'servicecheck-00-http-8080' on port 8080 is now passing.
```

On later boots the second line becomes `Admin account for … already exists, skipping.` Finally, from
outside:

```sh
curl -s -o /dev/null -w "%{http_code}\n" https://myapp-server.fly.dev/healthz
# 200
```

And, once, to see which dispatch the deployed binary got:

```sh
fly ssh console -C '/app/zonai version'
# Zonai: v0.6.2
# Ops/rules: in-process (project-linked)
```

The other answer is `worker IPC`, where ops and rules run as separate processes instead. Both serve
identically and nothing in the logs distinguishes them, which is exactly why it's worth asking once.

## Redeploying

The whole loop, every time:

```sh
./scripts/build_deploy_bundle.sh
fly deploy
fly status
```

The build script is not optional — `fly deploy` only packages whatever is currently in `build/`.
Skipping it silently ships your previous binaries.

## Verifying Locally (Optional)

If you'd rather not discover problems on Fly, the same image runs locally. On an ARM machine you need
the platform flag:

```sh
docker build --platform linux/amd64 -t myapp:verify .
docker volume create myapp-data

docker run -d --name myapp --platform linux/amd64 \
  -e ADMIN_EMAIL=verify@example.com \
  -e ADMIN_PASSWORD='verify-pw' \
  -e STRIPE_WEBHOOK_SECRET='test-secret' \
  -v myapp-data:/app/.zonai/data \
  -p 8099:8080 myapp:verify

docker logs myapp
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8099/healthz
```

Restarting the container against the same volume is a good check that your bootstrap script is
genuinely idempotent:

```sh
docker restart myapp && docker logs myapp | tail -5
```

Clean up with `docker rm -f myapp && docker volume rm myapp-data`.

## Don't Ship a Hardcoded `localhost` `baseUrl`

`AppConfig.baseUrl` is easy to leave hardcoded to `http://localhost:8080` during local development
and forget about — it compiles fine, `serve` never complains, and nothing breaks loudly. It just
means every absolute link the server generates (email templates, magic links, anything built from
`baseUrl`) silently points at `localhost` in production.

Read it from `.env` at build time, as in [step 2](#2-put-compile-time-config-in-env):

```dart
baseUrl: const String.fromEnvironment('BASE_URL', defaultValue: 'http://localhost:8080'),
```

`baseUrl` isn't a secret, so a runtime `Platform.environment['BASE_URL']` plus a `fly.toml` `[env]`
entry works too, and has the advantage of not needing a rebuild to change. Pick one — the failure
mode to avoid is a literal in the source.

Nothing checks this for you at build or boot time, so it's worth grepping your own `AppConfig` for
hardcoded `localhost` before every first production deploy, not just this one field.

## If the Server Segfaults on Boot

If a compiled `zonai serve` crashes with a segfault within a second of starting on Linux — this was a
real, deterministic bug (crossed-SQLite-build ABI mismatch inside `raindrop_sqlite`'s
`ResqliteDelegate.open`, opening one database file through two separately-built SQLite libraries)
that reproduced on every architecture. It's fixed upstream as of `zonai` `main` commit `3404812`
(plus `resqlite`/`raindrop` submodule pins). If you hit this, you're likely on a pre-fix commit — see
[known issue #12](https://github.com/mrgnhnt96/zonai/blob/main/docs/known-issues.md#12-compiled-zonai-serve-segfaults-seconds-after-startup-on-linux-x64arm64---sqlite3leavemutexandclosezombie---fixed)
for the full root cause rather than rediscovering it from scratch.

## Appendix: Rebuilding the Framework From Source

Everything above cross-compiles from your dev machine. This appendix is for a narrower case:
producing the `zonai` **CLI binary itself** from source — needed only if you're working on the zonai
framework, or you need a fix that isn't published as a release yet.

Two limitations a normal consumer deploy never hits:

- **`zonai build`'s own cross-compile support only produces `linux/x64`.** There is no cross-compile
  path to `linux/arm64` today, and a native `zonai build` on a `linux/arm64` machine fails outright
  with `Unsupported operation: Unsupported architecture: linux_arm64`.
- **Producing new prebuilt native libraries** (Argon2/libsodium, resqlite's `sqlite3mc` build)
  requires compiling them natively on each target OS. A consumer app's `zonai build` never does this
  — it links against the prebuilt libraries the framework ships.

The workable recipe, matching zonai's own CI (`.github/workflows/compile.yml` and the `zonai.compile`
script in `scripts.yaml`), is to build inside a genuine Linux container regardless of your host:

```sh
docker run --rm -it --platform linux/amd64 -v "$PWD":/work -w /work dart:stable bash
```

Inside the container:

```sh
apt-get update
apt-get install -y build-essential autoconf automake libtool m4 pkg-config cmake clang lld git ca-certificates
```

`build-essential` alone is **not** enough — the `autoconf`/`automake`/`libtool`/`m4` quartet is
required for the vendored libsodium/Argon2 build. Confirmed against a bare `dart:stable` container:
the build hook fails partway through without them.

If the repo has private submodules that need a GitHub token to fetch:

```sh
git config --global url."https://x-access-token:${GH_TOKEN}@github.com/".insteadOf "https://github.com/"
dart pub get
```

### Path A: Compile the CLI

1. For a full framework rebuild, run `tool/ci/use_revali_git_overrides.sh` first. It rewrites
   `pubspec_overrides.yaml` to point at git-based `revali` dependencies instead of local sibling-repo
   paths, which a container won't have.
2. Install [`sip`](https://github.com/mrgnhnt96/sip) and run the framework's compile pipeline:

   ```sh
   dart pub global activate --source git https://github.com/mrgnhnt96/sip.git --git-ref main
   dart pub global run sip_cli:sip run zonai compile
   ```

   This runs `version.gen`, `server.copy-to-cli`, `resqlite.gen`, `argon2.gen`, `web.gen`, then the
   final `dart compile exe` — roughly 24 minutes from a cold cache.

Compiling manually instead of via `sip` requires passing the compiled marker explicitly:

```sh
dart compile exe -D__ZONAI_COMPILED__=true bin/zonai.dart -o zonai
```

Without it, `zonai build`'s "copy the currently-running compiled binary" fast path never triggers and
it falls back to downloading a GitHub release — which fails for a private repo or an unpublished
version.

### Path B: Use a Release Binary

Prebuilt binaries ship as GitHub release assets (`zonai-linux-x64.zip`, `zonai-linux-arm64.zip`, …)
as of v0.3.4. Much faster than a from-scratch compile:

```sh
gh release list --repo mrgnhnt96/zonai
gh api repos/mrgnhnt96/zonai/releases/tags/vX.Y.Z
```

Because the repo is private, the auth header goes on the **asset download URL**, not just the
release-metadata call:

```sh
curl -L \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/octet-stream" \
  "<asset_url>" \
  -o zonai.zip

unzip zonai.zip
```

Verify you got the architecture you expect (`file zonai`) before trusting it.

### Then Build the App Bundle

Drop the Linux binary into your app directory, replacing the gitignored dev binary, and build as
normal — still inside the same `linux/amd64` container:

```sh
cp zonai path/to/your-app/server/zonai
cd path/to/your-app/server
./zonai build --release
```

From there, rejoin the main path at [step 4](#4-dockerfile).
