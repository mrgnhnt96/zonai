---
title: Trusted Proxies
description: Getting the real client IP when running behind a load balancer or reverse proxy.
---

When Zonai runs behind a reverse proxy, all TCP connections appear to come from the proxy's IP. Rate limiting becomes ineffective because every client shares the same counter. The real client IP is in a forwarded header like `X-Forwarded-For`.

## TrustedProxyConfig

Set `AppConfig.trustedProxy` to tell Zonai which headers to read and how to interpret them:

```dart in:app-config
trustedProxy: TrustedProxyConfig(
  headers: ['x-forwarded-for'],
  useLeftmostIp: false, // default — use rightmost (safer)
),
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `headers` | `List<String>` | `[]` | Header names to check, in order |
| `useLeftmostIp` | `bool` | `false` | Which IP to use from the header value |

## Leftmost vs. Rightmost

`X-Forwarded-For` contains a comma-separated chain of IPs appended at each hop:

```
X-Forwarded-For: client_ip, proxy1_ip, proxy2_ip
```

- **Rightmost (default, `useLeftmostIp: false`)** — reads the last IP in the chain. This is the IP your trusted proxy appended, which cannot be spoofed by the client. Use this when your proxy adds the `X-Forwarded-For` header itself and you trust it.
- **Leftmost (`useLeftmostIp: true`)** — reads the first IP in the chain. This is what the client claimed, and can be spoofed unless your proxy strips the header before forwarding. Only safe if you control the entire chain.

**Recommendation:** Use rightmost (the default) for standard nginx/Caddy setups.

## Multiple Headers

You can list multiple headers. Zonai checks them in order and uses the first one that is present:

```dart in:app-config
trustedProxy: TrustedProxyConfig(
  headers: ['cf-connecting-ip', 'x-forwarded-for'],
),
```

This example checks for Cloudflare's single-IP header first, falling back to the full `X-Forwarded-For` chain.

## Common Proxy Configurations

**nginx (standard)**
```nginx
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```
```dart in:expression
TrustedProxyConfig(headers: ['x-forwarded-for'], useLeftmostIp: false)
```

**Cloudflare**
```dart in:expression
TrustedProxyConfig(headers: ['cf-connecting-ip'])
```

**AWS ALB**
```dart in:expression
TrustedProxyConfig(headers: ['x-forwarded-for'], useLeftmostIp: false)
```
