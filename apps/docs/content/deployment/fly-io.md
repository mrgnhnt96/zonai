---
title: Deploying to Fly.io
description: Producing a Linux deploy bundle from macOS and running it on Fly.io.
---

This guide covers the parts of a Fly.io deployment that are specific to Fly and to cross-OS builds. For the basics of what `zonai build` produces, `--release` semantics, and process management, see [Building for Production](/deployment/building-for-production), [Release Mode](https://github.com/mrgnhnt96/zonai/blob/main/docs/release-mode.md), and [Running the Server](/deployment/running-the-server) first — this doc assumes you already know those.

## Why This Needs Its Own Guide

[Cross-Compilation](/deployment/cross-compilation) covers `buildSettings.targetOs`/`targetArch` for the common case of building on macOS and targeting Linux — but that only cross-compiles your **app's worker executables**. It does not help with two things a real Fly.io deploy also needs:

- **`zonai build`'s own cross-compile support only currently produces `linux/x64`.** There is no cross-compile path to `linux/arm64` today. A native `zonai build` run directly on a `linux/arm64` machine also fails outright:

  ```
  Unsupported operation: Unsupported architecture: linux_arm64
  ```

- **The `zonai` CLI binary itself cannot be cross-compiled from macOS to Linux.** It embeds native FFI dependencies — Argon2/libsodium (built via a build hook) and resqlite's own native `sqlite3mc` build — that must be compiled *natively on the target OS*, not cross-compiled. This is true whether you're rebuilding the framework from source or just producing a consumer app's `zonai build` bundle.

The workable recipe — matching what zonai's own CI does in `.github/workflows/compile.yml` and the `zonai.compile` script in `scripts.yaml` — is to do the actual build inside a genuine Linux container, regardless of your host OS/arch.

## The Docker-Based Linux Build

Run everything inside a `dart:stable` container targeting `linux/amd64` (Fly's default/most common machine architecture) — this gives you a real native Linux build environment whether your host is macOS Apple Silicon, macOS Intel, or something else entirely:

```sh
docker run --rm -it --platform linux/amd64 -v "$PWD":/work -w /work dart:stable bash
```

Inside the container, install the build toolchain:

```sh
apt-get update
apt-get install -y build-essential autoconf automake libtool m4 pkg-config cmake clang lld git ca-certificates
```

`build-essential` alone is **not** enough — the `autoconf`/`automake`/`libtool`/`m4` quartet specifically is required for the vendored libsodium/Argon2 build. This was confirmed against a bare `dart:stable` container: the build hook fails partway through without them.

If the repo you're building has private submodules (e.g. zonai's own `raindrop` submodule) that need a GitHub token to fetch:

```sh
git config --global url."https://x-access-token:${GH_TOKEN}@github.com/".insteadOf "https://github.com/"
dart pub get
```

From here there are two paths depending on what you're actually building.

### Path A: Rebuilding the zonai CLI from source

Only needed if you're working on the zonai framework itself, or need a version that isn't published as a GitHub release yet.

1. If you're doing a full framework rebuild (not just a consumer app), run `tool/ci/use_revali_git_overrides.sh` first. This rewrites `pubspec_overrides.yaml` to point at git-based `revali` dependencies instead of local sibling-repo paths — a Docker container won't have the local sibling checkout that a normal dev machine does.
2. Install [`sip`](https://github.com/mrgnhnt96/sip) and run the framework's own compile pipeline:

   ```sh
   dart pub global activate --source git https://github.com/mrgnhnt96/sip.git --git-ref main
   dart pub global run sip_cli:sip run zonai compile
   ```

   This runs the full pipeline (`version.gen`, `server.copy-to-cli`, `resqlite.gen`, `argon2.gen`, `web.gen`, then the final `dart compile exe`) and takes roughly 24 minutes from a cold cache.

If you compile manually instead of via `sip`, you must pass `-D__ZONAI_COMPILED__=true` to `dart compile exe` explicitly:

```sh
dart compile exe -D__ZONAI_COMPILED__=true bin/zonai.dart -o zonai
```

Without this define, `zonai build`'s "copy the currently-running compiled binary" fast path never triggers, and it falls back to downloading a GitHub release instead — which fails outright for a private repo or an unpublished version.

### Path B: Using an official release binary (faster, for consumer apps)

If you're just deploying a consumer app — not rebuilding zonai itself — this is much faster than a from-scratch compile. As of zonai v0.3.4, prebuilt binaries ship as GitHub release assets (`zonai-linux-x64.zip`, `zonai-linux-arm64.zip`, etc.).

Check what's available:

```sh
gh release list --repo mrgnhnt96/zonai
```

Then fetch the asset for a specific version. Because the repo is private, the auth header goes on the **asset download URL**, not just the release-metadata call:

```sh
# Get the asset's download URL from the release metadata
gh api repos/mrgnhnt96/zonai/releases/tags/vX.Y.Z

# Download the asset itself, with auth on this request too
curl -L \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/octet-stream" \
  "<asset_url>" \
  -o zonai.zip

unzip zonai.zip
```

Verify you got the architecture you expect (`file zonai`) before trusting it.

### Producing the app's deploy bundle

Whichever path you took, you now have a Linux `zonai` binary matching your target platform. Drop it into your consumer app's directory, replacing the gitignored dev binary:

```sh
cp zonai path/to/your-app/server/zonai
```

Then, still inside the same `dart:stable`/`linux/amd64` container, run a normal build against the consumer app's own source:

```sh
cd path/to/your-app/server
./zonai build --release
```

This produces the deploy bundle in `build/`, per [Building for Production](/deployment/building-for-production).

## Runtime Gotcha: `libsqlite3`

The `build/` bundle's workers link against `libsqlite3`. The runtime container should be a lean image — `debian:bookworm-slim`, not `dart:stable` — but Debian's `libsqlite3-0` package only ships the versioned `libsqlite3.so.0` file, not the unversioned `libsqlite3.so` symlink that FFI loaders look for by default. That symlink normally only comes from the much heavier `-dev` package. Create it manually instead:

```sh
ln -sf /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /usr/lib/x86_64-linux-gnu/libsqlite3.so
```

## Dockerfile

Since the build already happened outside Docker (in the ephemeral build container above), the runtime Dockerfile doesn't need to be multi-stage — it just packages the prebuilt `build/` directory:

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends ca-certificates libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /usr/lib/x86_64-linux-gnu/libsqlite3.so

WORKDIR /app
COPY build/ .

EXPOSE 8080
CMD ["./zonai", "serve", "--release", "--host", "0.0.0.0"]
```

`.dockerignore` only needs to let the prebuilt bundle through — Fly's build context doesn't need your app's source at all:

```
*
!build/
!Dockerfile
```

## fly.toml

Zonai's own SQLite database (`zonai.sqlite`) lives under `.zonai/data` inside the app directory (`Settings.defaultZonaiDirectory` + `data`, per zonai's source). Mount a persistent volume there so data survives redeploys and restarts:

```toml
app = "wholesale-command-station-server"
primary_region = "iad"

[build]

[env]
  PORT = "8080"

[[mounts]]
  source = "wcs_data"
  destination = "/app/.zonai/data"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "off"
  auto_start_machines = true
  min_machines_running = 1

  [[http_service.checks]]
    interval = "15s"
    timeout = "5s"
    grace_period = "10s"
    method = "GET"
    path = "/health"

[[vm]]
  size = "shared-cpu-1x"
  memory = "512mb"
```

## Creating the App and Volume

The volume must exist before the first deploy:

```sh
fly apps create wholesale-command-station-server --org <your-org>
fly volumes create wcs_data --app wholesale-command-station-server --region iad --size 1
```

## Deploying

```sh
fly deploy --local-only
```

`--local-only` builds the Docker image locally via Docker Desktop instead of Fly's remote builder. This matters here because the whole build pipeline above was pinned to `--platform linux/amd64` explicitly — using the local builder keeps you in control of the final image architecture regardless of your host machine's architecture pulling the base image, so it matches what Fly machines actually run.

## First Boot: Creating an Admin Account

`zonai serve` auto-applies pending migrations on startup, but that's the only thing that happens automatically. A brand-new deployment has zero admin accounts and no sign-up screen, so sign-in will fail with a generic "check your email and password" error until you seed one. Run it once against the live deployment:

```sh
fly ssh console -C './zonai db admin add -e admin@example.com -p secret123'
```

See [Admin Accounts](/authentication/admin-accounts) and [`zonai db`](/cli/db) for the full flag reference.

## If the Server Segfaults on Boot

If a compiled `zonai serve` crashes with a segfault within a second of starting on Linux — this was a real, deterministic bug (crossed-SQLite-build ABI mismatch inside `raindrop_sqlite`'s `ResqliteDelegate.open`, opening one database file through two separately-built SQLite libraries) that reproduced on every architecture. It's fixed upstream as of `zonai` `main` commit `3404812` (plus `resqlite`/`raindrop` submodule pins). If you hit this, you're likely on a pre-fix commit — see [known issue #12](https://github.com/mrgnhnt96/zonai/blob/main/docs/known-issues.md#12-compiled-zonai-serve-segfaults-seconds-after-startup-on-linux-x64arm64---sqlite3leavemutexandclosezombie---fixed) for the full root cause and fix commits rather than rediscovering it from scratch.
