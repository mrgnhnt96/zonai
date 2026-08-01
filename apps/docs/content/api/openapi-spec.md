---
title: OpenAPI Specification
description: Fetch the auto-generated OpenAPI spec for your Zonai API.
---

Zonai exposes a machine-readable description of every HTTP route on the server. Use it to explore the API, generate clients, or import routes into Postman or Swagger UI.

## Endpoints

| Route               | Content-Type       | Description              |
| ------------------- | ------------------ | ------------------------ |
| `GET /swagger.json` | `application/json` | OpenAPI 3.0 spec as JSON |
| `GET /swagger.yaml` | `text/yaml`        | Same spec as YAML        |

Both routes are public — no authentication required.

## Fetching the spec

```sh
curl http://localhost:8080/swagger.json
curl http://localhost:8080/swagger.yaml
```

Replace the host and port with your server's binding. Defaults are `localhost:8080`; see [Server Binding](/deployment/server-binding).

## What is included

The spec is generated from your server's route definitions and request/response types. It covers:

- Database CRUD routes (`/db`, `/db/list`, `/db/count`, `/db/many`, …)
- **Live query streams** (`/db/stream`, `/db/stream/list`, `/db/stream/count`) — see [Streaming](/operations/streaming)
- Authentication routes (`/auth/sign-up`, `/auth/sign-in`, …)
- Photo upload and serving (`/img`)
- Dashboard metrics (`/dashboard/metrics`)
- Email sending (`/email`)
- Built-in health check (`/health`)
