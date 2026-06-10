---
title: Running the Server
description: How to start Zonai in production mode.
---

## Starting the Server

From the build directory, always use `--release` in production:

```sh
./zonai serve --release
```

Without `--release`, the server tries to watch source files that do not exist in the bundle and enters dev mode.

## Startup Sequence

1. Load `zonai.yaml` for paths and configuration
2. Start all worker processes from `.zonai/executables/`
3. Apply pending migrations (unless `--no-auto-migrate`)
4. Ping each worker to confirm readiness
5. Open the HTTP listener

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
