---
title: zonai dev
description: The recommended development command — runs the server with an interactive TUI and dev helpers.
---

Start the Zonai server and open an interactive terminal UI (TUI) for development.

```sh
zonai dev [flags]
```

`--host` and `--port` use the same precedence as `zonai serve` (CLI → `zonai.yaml` → defaults). See [Server Binding](/deployment/server-binding).

`zonai dev` is the go-to command during development. It runs the server and wraps it in a TUI that provides live feedback and shortcuts for common tasks.

<Info>
While developing Flutter/Dart clients, use `zonai_client` `db.listen` against the local server — live queries are available in dev too. See [Streaming](/operations/streaming).
</Info>

## TUI Features

- **Schema viewer** — browse defined tables and their columns
- **Operations tester** — test CRUD operations against the running database
- **Migration helper** — generate and apply schema migrations without leaving the terminal
- **Admin management** — create and manage admin accounts
- **Run cron job** — trigger a cron job immediately by name (`j`)
- **Worker status** — see which workers are running and restart them on demand

## Project Initialization

If `zonai.yaml` does not exist in the current directory, `zonai dev` prompts you to create one, guiding you through selecting source paths and initial settings.

## `zonai dev` vs `zonai serve`

|                      | `zonai dev` | `zonai serve`              |
| -------------------- | ----------- | -------------------------- |
| Runs the HTTP server | ✓           | ✓                          |
| Interactive TUI      | ✓           | —                          |
| Migration helpers    | ✓           | auto-apply on startup only |
| Schema viewer        | ✓           | —                          |

<Info>
Use `zonai serve` when you want the server without the TUI — for example, to get a closer-to-production environment during development, or to run in CI. Use `zonai serve --release` for production.
</Info>
