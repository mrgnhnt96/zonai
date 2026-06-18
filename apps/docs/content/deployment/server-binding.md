---
title: Server Binding
description: Configuring which host and port the server listens on.
---

## Defaults

```
host: localhost
port: 8080
```

When `host` is `localhost` (the default), the server binds dual-stack on `::` so both IPv4 and IPv6 clients can connect. For production behind a reverse proxy, set `host: 127.0.0.1` to listen on IPv4 loopback only. Set `host: 0.0.0.0` to listen on all IPv4 interfaces.

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

## When to Override `host`

Override the default `localhost` binding when:

- **Production behind a reverse proxy** — use `host: 127.0.0.1` so the process listens on loopback only
- **IPv4 all interfaces explicitly** — use `host: 0.0.0.0`
- **The server is not behind a reverse proxy** and must accept external connections directly on IPv4

## `localhost` (dual-stack default)

When `host` is `localhost` (the built-in default), the server binds dual-stack on `::` with `v6Only: false`. Both IPv4 and IPv6 clients work out of the box — including `curl http://127.0.0.1:8080` and emulators via `10.0.2.2`.

To restrict binding:

```sh
# IPv4 loopback only (typical behind nginx/Caddy)
zonai serve --host 127.0.0.1

# IPv4 on all interfaces
zonai serve --host 0.0.0.0
```

Or set `host:` in `zonai.yaml`. The same flags apply to `zonai dev`.

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
