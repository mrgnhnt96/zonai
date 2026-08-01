---
title: Introduction
description: What Zonai is, who it's for, and the problem it solves.
---

Zonai is a Dart backend-as-a-service framework that turns schema definitions into a complete REST API. Write your tables, rules, and business logic in Dart — Zonai handles the HTTP layer, the database, and the auth system.

It is designed for Dart and Flutter developers who want to build a production-quality backend without wiring together boilerplate.

## What You Get Out of the Box

**A full REST API for every table** — create, read, update, delete, list, and count endpoints are auto-handled from your schema. No HTTP handler code, no generation step needed.

**Built-in authentication** — password sign-up/sign-in, one-time passcodes, and magic links are available by mixing a single trait into an auth table. Sessions, refresh, and logout are included.

**Authorization rules** — evaluated before any SQL executes. Return `true` or `false`; a denied request gets a `403` immediately, with zero database access.

**Transactional email via SMTP** — HTML templates with Mustache variables, sent from lifecycle hooks.

**Scheduled background jobs** — cron-syntax jobs compiled into a separate worker with access to the full database API.

**Per-IP rate limiting** — configurable per-table and per-operation with a simple policy class.

**Project-linked binary** — `zonai build` produces `build/zonai` with your ops/rules linked in-process for the CRUD hot path.

## How It Works

Your Dart code compiles into a **project-linked server binary** (operations and rules in-process) plus **workers** for config, extensions, rate limits, and crons. Each HTTP request passes through an ordered pipeline:

```
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

- Not a full application framework — Zonai is an API server only (no HTML rendering, no client library)
- Not a managed cloud service — you host it yourself, anywhere that runs a Linux/macOS/Windows binary
- Not a general-purpose ORM — it is opinionated about how APIs are structured and uses SQLite as its database

## Next Steps

- [Installation](/getting-started/installation) — prerequisites and CLI setup
- [Quick Start](/getting-started/quick-start) — create and run your first project
- [Project Structure](/getting-started/project-structure) — understand the directory layout
