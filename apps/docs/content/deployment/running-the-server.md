---
title: Running the Server
description: How to start Zonai in production mode.
---

## Starting the Server

From the build directory, always use `--release` in production:

```sh
./zonai serve --release
```

Without `--release`, `serve` runs in development mode: it watches for source files that do not exist in the bundle and tries to recompile workers. See [Release mode](/deployment/building-for-production#release-mode) for everything the flag changes.

Host and port come from the bundled `zonai.yaml` unless you pass `--host` / `--port` — see [Server Binding](/deployment/server-binding).

## What Happens at Startup

- Load `zonai.yaml` for paths, host and port
- Start the workers from `.zonai/executables/` (operations and rules run in-process instead when `build/zonai` is project-linked)
- Validate `AppConfig` — a missing or weak secret stops the server here
- Open the database and apply any pending migrations
- Open the HTTP listener

## Process Management

Use a process manager to keep the server running and restart it on failure.

**systemd (Linux)**

```ini
[Unit]
Description=Zonai server
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/zonai serve --release
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl enable --now myapp
```

**Docker**

```dockerfile
FROM debian:bookworm-slim
WORKDIR /app
COPY build/ .
EXPOSE 8080
CMD ["./zonai", "serve", "--release", "--host", "0.0.0.0"]
```

## Graceful Shutdown

Send `SIGTERM` (or `SIGINT` / Ctrl+C) to shut down gracefully. In-flight requests complete before the process exits; workers are shut down cleanly afterward.

## Health Checks

Zonai exposes a built-in health endpoint at `GET /health`. Use it to verify the server is up and accepting requests.

## OpenAPI Spec

The full API surface is described at `GET /swagger.json` and `GET /swagger.yaml`. Import either URL into Swagger UI, Postman, or an OpenAPI code generator. See [OpenAPI Specification](/api/openapi-spec).
