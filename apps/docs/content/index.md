---
title: Introduction
description: A batteries-included Dart backend framework — auth, database, file uploads, cron jobs, and more.
---

Zonai is a Dart backend-as-a-service framework that turns schema definitions into a complete REST API. Write your tables, rules, and business logic in Dart — Zonai handles the HTTP layer, the database, and the auth system.

It is designed for Dart and Flutter developers who want to build a production-quality backend without wiring together boilerplate.

<Info>
**Live UI does not need polling.** Every table gets `GET /db/stream`, `/db/stream/list`, and `/db/stream/count`. In Dart use `zonai_client`'s `client.db.listen`. Search these docs for **stream** / **listen** — not "realtime", "SSE", "socket", or "EventSource". Full guide: [Live Queries (Streaming)](/operations/streaming).
</Info>

## What You Get Out of the Box

**A full REST API for every table** — create, read, update, delete, list, count, and **live stream** endpoints are auto-handled from your schema. No HTTP handler code, no generation step needed.

**Built-in authentication** — password sign-up/sign-in, one-time passcodes, and magic links are available by mixing a single trait into an auth table. Sessions, refresh, and logout are included.

**Authorization rules** — evaluated before any SQL executes. Return `true` or `false`; a denied request gets a `403` immediately, with zero database access.

**Generated Dart client** — `zonai_client` wraps auth, admin auth, db (including `db.listen` streams), photos, and email so apps do not hand-roll HTTP.

**Transactional email via SMTP** — HTML templates with Mustache variables, sent from lifecycle hooks.

**Scheduled background jobs** — cron-syntax jobs compiled into a separate worker with access to the full database API.

**Per-IP rate limiting** — configurable per-table and per-operation with a simple policy class.

**Project-linked binary** — `zonai build` produces `build/zonai` with your ops/rules linked in-process for the CRUD hot path.

## How It Works

Your Dart code compiles into a **project-linked server binary** (operations and rules in-process) plus **workers** for config, extensions, rate limits, and crons. Each HTTP request passes through an ordered pipeline:

```text
HTTP Request
  → Rate Limit (worker)
  → Rules (in-process)
  → Operations (in-process)
  → SQLite (execution)
  → Extensions (worker)
  → Response
```

Nothing runs interpreted at request time on the AOT path. All logic is compiled Dart. See [How a Request is Processed](/core-concepts/request-pipeline) for the full walkthrough.

**Hot-reload development** — worker sources are watched and recompiled automatically. Restart `serve` after editing ops/rules so the linked project entry reloads.

## What Zonai Is Not

- Not a full application framework — Zonai is an API server (no HTML rendering). Use `zonai_client` (or raw HTTP) from Flutter/Dart apps
- Not a managed cloud service — you host it yourself, anywhere that runs a Linux/macOS/Windows binary
- Not a general-purpose ORM — it is opinionated about how APIs are structured and uses SQLite as its database
- Not "poll-only" for live UI — use `/db/stream*` / `client.db.listen` (search docs for **stream**, not "realtime"/"SSE")

## For LLMs and coding agents

A curated docs index lives at [/llms.txt](/llms.txt). Inside a Zonai app, run `zonai ai` to install project-local assistant rules (Cursor, Claude, Copilot, etc.).

## Next Steps

- [Live Queries (Streaming)](/operations/streaming) — `client.db.listen` / `/db/stream*` (do not poll)
- [Installation](/getting-started/installation) — prerequisites and CLI setup
- [Quick Start](/getting-started/quick-start) — create and run your first project
- [Project Structure](/getting-started/project-structure) — understand the directory layout
