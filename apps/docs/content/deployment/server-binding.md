---
title: Server Binding
description: Configuring which host and port the server listens on.
---

## Defaults

```
host: localhost   → binds 127.0.0.1 (IPv4 loopback)
port: 8080
```

An unconfigured server is reachable **from this machine only**. The default `localhost` is bound as the IPv4 loopback literal `127.0.0.1` — not resolved through DNS, so it can't land on IPv6-only `[::1]` the way `localhost` does on macOS. `curl http://127.0.0.1:8080`, `http://localhost:8080` and the Android emulator's `10.0.2.2` all reach it.

Any other value is bound exactly as written. Exposing the server beyond the machine is always an explicit choice.

| `host` | Listens on |
| --- | --- |
| `localhost` (default) | `127.0.0.1` only |
| `127.0.0.1` | IPv4 loopback only |
| `::1` | IPv6 loopback only — use this if you need `http://[::1]:8080` |
| `0.0.0.0` | Every IPv4 interface — required inside Docker/containers and for direct external access |

## Configuration Precedence

From highest to lowest priority:

1. CLI flags: `--host`, `--port` (`--host 0.0.0.0` and `--host=0.0.0.0` both work)
2. `zonai.yaml`: `host:`, `port:`
3. Built-in defaults: `localhost:8080`

The same flags work with `zonai serve` and `zonai dev`.

## Setting in zonai.yaml

```yaml
host: 0.0.0.0
port: 8091
```

`zonai build` copies your `zonai.yaml` into `build/`, so a server started from that directory uses the same host and port unless you pass flags at launch.

## Setting via CLI

```sh
zonai serve --host 0.0.0.0 --port 9000

# From a build/ bundle
./zonai serve --release --host 0.0.0.0
```

## Recommended: Reverse Proxy

The recommended production pattern is a reverse proxy in front of Zonai. The proxy handles TLS, compression, and HTTP/2 while Zonai keeps the default loopback binding:

**nginx**

```nginx
server {
  listen 443 ssl;
  server_name api.myapp.com;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $host;
  }
}
```

**Caddy**

```
api.myapp.com {
  reverse_proxy 127.0.0.1:8080
}
```

Behind a proxy, every request arrives from the proxy's address. For rate limiting and logs to see the real client, set [`trustedProxy`](/configuration/app-config#trusted-proxy) on `AppConfig` and make sure the proxy **sets or overwrites** that header — see [Trusted Proxies](/rate-limiting/trusted-proxies).

## baseUrl vs. Binding

`AppConfig.baseUrl` is the **public-facing URL** used to build links in auth emails (password reset, magic link, email verification) and OAuth redirects. The `host`/`port` binding is only where the process listens. They default to matching values (`http://localhost:8080` and `localhost:8080`), so when you change either one — a different port locally, or a public domain in production — set `baseUrl` to the URL clients actually use:

```dart in:app-config
baseUrl: 'https://api.myapp.com',  // for email links
// server actually listens on 127.0.0.1:8080 behind nginx
```
