---
title: CORS and Allowed Origins
description: Which browser origins get a credentialed CORS grant, and how ZONAI_ALLOWED_ORIGINS adds your own front end.
---

A browser only hands a cross-origin page the reply when the response says it may, through `Access-Control-Allow-*` headers. Zonai decides those headers per request, from the request's `Origin` header. There are two grants:

- **Credentialed:** `Access-Control-Allow-Origin` is the caller's own origin and `Access-Control-Allow-Credentials: true` is set. The page may send cookies and HTTP auth with the request (`credentials: 'include'`) and read the reply.
- **Public:** `Access-Control-Allow-Origin: *` with no `Access-Control-Allow-Credentials`. The page can read the reply, but the browser refuses any request that sends cookies or HTTP auth.

## Who gets which grant

| Request `Origin` | Grant |
| --- | --- |
| A loopback origin: `localhost`, `127.0.0.1` or `[::1]`, over `http` or `https`, on any port | Credentialed |
| An exact entry in `ZONAI_ALLOWED_ORIGINS` | Credentialed |
| Any other origin | Public |
| No `Origin` header (native apps, `curl`, server-to-server calls) | Public. These are not browser cross-origin requests, so CORS does not limit them |

The same grant goes on every response for that request: the `OPTIONS` preflight, the real request, an error, and the `404` for a route that does not exist. Every response also carries `Vary: Origin`, so a shared cache never replays one origin's grant to another.

CORS is not access control. A request from an unlisted origin still reaches your routes and your rules; the grant only decides what the browser lets the page see and send. A web app that signs in with Zonai's bearer tokens works from any origin with the public grant.

## Allowing your front end: `ZONAI_ALLOWED_ORIGINS`

List the origins that need the credentialed grant, comma-separated:

```bash
ZONAI_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com \
  ./zonai serve --release
```

Add an origin when a page served from it sends credentials, for example `fetch(url, {credentials: 'include'})`. Without the entry, the browser rejects that request even though the server answered it.

- Each entry is an exact origin: scheme, host and, when it is not the default, port. `https://app.example.com` does not cover `https://app.example.com:8443`, `http://app.example.com` or `https://www.example.com`.
- Leave off any trailing slash or path. A browser's `Origin` header never has one, so `https://app.example.com/` never matches.
- There are no wildcards or patterns. List each origin you need.
- Spaces around entries and empty entries are ignored. Unset or empty means only the loopback origins get the credentialed grant.

The variable is read from the server's process environment, not compiled into the binary, so a released build can point at a deployment's front end without being rebuilt. Like the other [runtime variables](/configuration/environment-variables#runtime-tuning-zonai_), it is not loaded from `.env`: set it in your shell, service unit or host's secret store before the server starts. On Fly.io, for example:

```bash
fly secrets set ZONAI_ALLOWED_ORIGINS=https://app.example.com
```

## The dashboard

The dashboard at `/_` is served by the same server it calls, so its requests are same-origin and CORS does not apply to them.
