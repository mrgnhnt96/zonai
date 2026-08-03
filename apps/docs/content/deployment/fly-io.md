---
title: Deploying to Fly.io
description: Producing a Linux deploy bundle from macOS and running it on Fly.io.
---

This guide covers the parts of a Fly.io deployment that are specific to Fly and to cross-OS builds. For the basics of what `zonai build` produces, `--release` semantics, and process management, see [Building for Production](/deployment/building-for-production), [Release Mode](https://github.com/mrgnhnt96/zonai/blob/main/docs/release-mode.md), and [Running the Server](/deployment/running-the-server) first — this doc assumes you already know those.

## Do You Even Need Docker?

**Probably not.** If you're deploying a normal consumer app — no changes to the zonai framework itself, just your own schemas/rules/config — set `buildSettings.targetOs`/`targetArch` in `zonai.yaml` and run `zonai build --flavor prod --release` on your dev machine. See [Cross-Compilation](/deployment/cross-compilation). This produces a native Linux `build/` bundle directly via `dart compile exe`. No container runtime, no GitHub token, nothing else required — go straight to packaging that bundle into a minimal runtime image (see the plain `Dockerfile` at the bottom of this guide, which just copies `build/` — it doesn't build anything).

The rest of this guide, specifically the **Docker-Based Linux Build** section below, is for a narrower and much less common case: producing the `zonai` **CLI binary itself** from source — needed only if you're working on the zonai framework, or you need a fix/version that isn't published as a release yet. If your locally-installed `zonai` already builds and serves your app correctly, you don't need any of that; skip to [Producing the app's deploy bundle](#producing-the-apps-deploy-bundle).

## Why the From-Source Path Needs Its Own Guide

A consumer app's `buildSettings`-driven `zonai build` genuinely cross-compiles end to end — the project binary and workers, including the parts that link against Argon2/libsodium and resqlite's native `sqlite3mc` build, all come out as real target-OS binaries with no native toolchain on the host. That's because those native libraries are **already built** (shipped as prebuilt platform binaries by the framework) — a consumer build links against the existing one for your target, it doesn't recompile any C from source.

Rebuilding the zonai CLI framework itself is a different task, with two real limitations that a normal consumer deploy never hits:

- **`zonai build`'s own cross-compile support only currently produces `linux/x64`.** There is no cross-compile path to `linux/arm64` today. A native `zonai build` run directly on a `linux/arm64` machine also fails outright:

  ```
  Unsupported operation: Unsupported architecture: linux_arm64
  ```

- **Producing new prebuilt native libraries (Argon2/libsodium, resqlite's `sqlite3mc` build) requires compiling them natively on each target OS** — this only comes up when you're changing the framework's native code or need those libraries for a platform they haven't been built for yet. It is not something a consumer app's `zonai build` ever does.

If you need to rebuild the framework from source for one of those reasons, the workable recipe — matching what zonai's own CI does in `.github/workflows/compile.yml` and the `zonai.compile` script in `scripts.yaml` — is to do the actual build inside a genuine Linux container, regardless of your host OS/arch.

## The Docker-Based Linux Build (Framework Rebuilds Only)

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

## Don't Ship a Hardcoded `localhost` `baseUrl`

`AppConfig.baseUrl` (see [Config](/configuration/zonai-yaml)) is easy to leave hardcoded to
`http://localhost:8080` during local development and forget about — it compiles fine, `serve` never
complains, and nothing breaks loudly. It just means every absolute link the server generates (email
templates, magic links, anything built from `baseUrl`) silently points at `localhost` in production
instead of your real domain.

Read it from an environment variable with a `localhost` fallback instead, the same way you'd handle
`passwordSecret`/`jwtSecret`:

```dart
AppConfig main() {
  return AppConfig(
    // ...
    baseUrl: Platform.environment['BASE_URL'] ?? 'http://localhost:8080',
  );
}
```

Then set the real value in `fly.toml`'s `[env]` block — it isn't a secret, so it doesn't need `fly
secrets set`:

```toml
[env]
  BASE_URL = "https://your-app.fly.dev"
```

Nothing checks this for you at build or boot time, so it's worth grepping your own `AppConfig` for
hardcoded `localhost` before every first production deploy, not just this one field.

## First Boot: Creating an Admin Account

`zonai serve` auto-applies pending migrations on startup, but that's the only thing that happens automatically. A brand-new deployment has zero admin accounts and no sign-up screen, so sign-in will fail with a generic "check your email and password" error until you seed one. Run it once against the live deployment:

```sh
fly ssh console -C './zonai db admin add -e admin@example.com -p secret123'
```

See [Admin Accounts](/authentication/admin-accounts) and [`zonai db`](/cli/db) for the full flag reference.

## If the Server Segfaults on Boot

If a compiled `zonai serve` crashes with a segfault within a second of starting on Linux — this was a real, deterministic bug (crossed-SQLite-build ABI mismatch inside `raindrop_sqlite`'s `ResqliteDelegate.open`, opening one database file through two separately-built SQLite libraries) that reproduced on every architecture. It's fixed upstream as of `zonai` `main` commit `3404812` (plus `resqlite`/`raindrop` submodule pins). If you hit this, you're likely on a pre-fix commit — see [known issue #12](https://github.com/mrgnhnt96/zonai/blob/main/docs/known-issues.md#12-compiled-zonai-serve-segfaults-seconds-after-startup-on-linux-x64arm64---sqlite3leavemutexandclosezombie---fixed) for the full root cause and fix commits rather than rediscovering it from scratch.
