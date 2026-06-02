# Server host and port

Zonai’s HTTP server binds to a **host** and **port** when you run `serve` or a compiled deployment. Configure them in `zonai.yaml` for a stable default, or override per run with CLI flags.

Both settings are resolved from the **current working directory** when you run `dart run zonai` (typically your app root, e.g. `apps/playground`).

## Precedence

| Priority    | Source                     | Example                        |
| ----------- | -------------------------- | ------------------------------ |
| 1 (highest) | CLI flags                  | `--host 0.0.0.0 --port 8091`   |
| 2           | `zonai.yaml` / `zonai.yml` | `host: 0.0.0.0` / `port: 8091` |
| 3 (default) | Built-in defaults          | `localhost` / `8080`           |

CLI flags always win for that process. Values in `zonai.yaml` apply when a flag is not passed.

## CLI flags

From your app directory (where `zonai.yaml` lives):

```bash
# Listen on all interfaces, port 8091
dart run zonai serve --host 0.0.0.0 --port 8091

# Override only the port
dart run zonai serve --port 3000

# Equals form also works
dart run zonai serve --host=127.0.0.1 --port=8080
```

Use `--host 0.0.0.0` when the server runs inside a container or on a remote machine and must accept connections from outside `localhost`.

## Client IP behind a reverse proxy

When nginx, Traefik, Coolify, Cloudflare, or another proxy sits in front of Zonai, rate limits and logs need the **real client IP**, not the proxy’s. Configure **`trustedProxy`** on `AppConfig` in your config worker — see **[rate-limiting.md](rate-limiting.md#client-ip)** for the full example and semantics (rightmost vs leftmost IP in `X-Forwarded-For`).

Ensure your proxy **sets** or **overwrites** the chosen header; do not rely on client-supplied `X-Forwarded-For` unless the edge strips untrusted values.

## `zonai.yaml`

Add optional `host` and `port` keys alongside your other project settings:

```yaml
version: 0.1.0

host: 0.0.0.0
port: 8091

migrationsPath: .zonai/migrations
schemasPath: lib/src/schemas
configPath: lib/src/config
```

When you run `dart run zonai build`, your settings file is copied into the build output (under `build/`, keeping the same filename), so deployments started from that directory pick up the same host and port unless overridden at launch. See **[release-mode.md](release-mode.md)** for the full `build/` layout and production workflow.

## Public URLs in app config (`baseUrl`)

Server binding is separate from **`AppConfig.baseUrl`** in your config worker (`lib/src/config/db_config*.dart`). `baseUrl` is the public URL Zonai uses in emails and auth links (magic links, password reset, email verification). See **[email.md](email.md)** for template and SMTP setup.

If you change host or port, set `baseUrl` to the URL clients actually use:

```dart
AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: '...',
    jwtSecret: '...',
    baseUrl: 'http://localhost:8091',
  );
}
```

Defaults: server binds to `localhost:8080`; `AppConfig.baseUrl` defaults to `http://localhost:8080`. Keep them aligned when you use a non-default port or a hostname other than `localhost`.

## Examples

**Local dev on the default port** — omit both settings; no flags needed:

```bash
dart run zonai serve
# → http://localhost:8080
```

**Fixed port in config, host overridden for Docker**:

`zonai.yaml`:

```yaml
port: 8091
```

```bash
dart run zonai serve --host 0.0.0.0
# → http://0.0.0.0:8091
```

**Production-style compiled run** — set host and port in `zonai.yaml` before `zonai build`, then from the `build/` directory:

```bash
cd build
./zonai serve --release
# optional overrides: ./zonai serve --release --host 0.0.0.0 --port 8091
```

The copied `zonai.yaml` in `build/` supplies defaults; CLI flags still win at runtime.
