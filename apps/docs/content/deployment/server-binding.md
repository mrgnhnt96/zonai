---
title: Server Binding
description: Configuring which host and port the server listens on.
---

## Defaults

```
host: localhost
port: 8080
```

`localhost` only accepts connections from the same machine. For production, set `host: 0.0.0.0` to accept connections on all interfaces.

## Configuration Precedence

From highest to lowest priority:

1. CLI flags: `--host`, `--port`
2. `zonai.yaml`: `host:`, `port:`
3. Built-in defaults: `localhost:8080`

## Setting in zonai.yaml

```yaml
host: 0.0.0.0
port: 8080
```

## Setting via CLI

```sh
zonai serve --host 0.0.0.0 --port 9000
```

## When to Use 0.0.0.0

Bind to `0.0.0.0` when:
- The server is not behind a reverse proxy and needs to accept external connections directly
- Running inside Docker — `localhost` inside the container is not reachable from the host
- Developing with an **emulator** — the emulator reaches the host at `10.0.2.2` (IPv4 only)

## `localhost` (IPv4 vs IPv6)

The default `localhost` bind address may listen on IPv6 loopback (`[::1]`) only. IPv4 clients — including `curl http://127.0.0.1:8080` and emulators via `10.0.2.2` — see **Connection refused** even though the server is up.

**Symptoms:** `lsof` shows `TCP [::1]:8080 (LISTEN)` but not `127.0.0.1`.

**Fix:** override the bind address:

```sh
zonai serve --host 0.0.0.0
# or IPv4 loopback only:
zonai serve --host 127.0.0.1
```

Or set `host: 0.0.0.0` in `zonai.yaml`. The same flags apply to `zonai dev`.

## Recommended: Reverse Proxy

The recommended production pattern is a reverse proxy in front of Zonai. The proxy handles TLS, compression, and HTTP/2 while Zonai stays on `localhost`:

**nginx**

```nginx
server {
  listen 443 ssl;
  server_name api.myapp.com;
  location / {
    proxy_pass http://localhost:8080;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $host;
  }
}
```

**Caddy**

```
api.myapp.com {
  reverse_proxy localhost:8080
}
```

## baseUrl vs. Binding

`AppConfig.baseUrl` is the **public-facing URL** used in email links (e.g. `https://api.myapp.com`). The `host`/`port` binding is where the server process listens. These are independent:

```dart
baseUrl: 'https://api.myapp.com',  // for email links
// server actually listens on localhost:8080 behind nginx
```
