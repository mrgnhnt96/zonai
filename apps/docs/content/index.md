---
title: Zonai
description: A batteries-included Dart backend framework — auth, database, live query streams, file uploads, cron jobs, and more.
---

Zonai is a Dart backend-as-a-service framework that turns schema definitions into a complete REST API. Write your tables, rules, and business logic in Dart — Zonai handles the HTTP layer, the database, and the auth system.

It is designed for Dart and Flutter developers who want to build a production-quality backend without wiring together boilerplate.

<CardGrid columns="3">

<Card title="Quick Start" href="/getting-started/quick-start" icon="rocket">

Go from an empty folder to a running server with auth and CRUD in about ten minutes.

</Card>

<Card title="Live Queries" href="/operations/streaming" icon="bolt" badge="live">

`client.db.listen` and `/db/stream*` push updates as SQLite data changes.

</Card>

<Card title="Dart Client" href="/dart-client/overview" icon="dart">

`zonai_client` wraps auth, db, photos and email so apps never hand-roll HTTP.

</Card>

</CardGrid>

## Start Here

1. [Installation](/getting-started/installation) — what to install, and how to get the `zonai` binary
2. [Quick Start](/getting-started/quick-start) — create a project, add tables, call the API, open the dashboard, build for production
3. [Project Structure](/getting-started/project-structure) — which files are required, which are optional, and what to commit

## Write a table, get an API

Define a table in Dart:

```dart no-analyze
final class TaskTable extends Table<Task> {
  TaskTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: TasksId.new, generate: TasksId.generate),
      title = $.text('title', (s) => s.title),
      isComplete = $.boolean('is_complete', (s) => s.isComplete),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  // …
}

final tasks = table('tasks', TaskTable.new);
```

Every endpoint below is served for it — no handlers to write. The only other things a table needs are a [rules file](/rules/overview) (tables start closed) and an applied migration:

```text
POST   /db          create        GET  /db/stream        live single row
GET    /db          read          GET  /db/stream/list   live list
PATCH  /db          update        GET  /db/stream/count  live count
DELETE /db          delete
GET    /db/list     list          POST /auth/sign-up     from an AuthTable
GET    /db/count    count         POST /auth/sign-in
```

And live UI is a subscription, not a timer:

```dart no-analyze
client.db.listen
    .list(body: StreamListBody(table: 'tasks'), fromJson: Task.fromJson)
    .listen((tasks) => setState(() => _tasks = tasks));
```

## What You Get Out of the Box

- **A REST API for every table** — create, read, update, delete, list, count, and live stream endpoints, served from your schema. No handler code.
- **Authentication** — password, one-time passcode, and magic-link sign-in by mixing a trait into an auth table. Sessions and logout included.
- **Authorization rules** — checked before any SQL runs. A denied request gets `403` with zero database access. Tables start closed.
- **Dart client** — `zonai_client` wraps auth, db (including `db.listen` streams), photos, and email; `zonai gen client` adds typed per-table APIs.
- **Email and push** — SMTP with Mustache templates, and push through FCM or APNs, sent from lifecycle hooks. See [Push Overview](/push/overview).
- **Cron jobs and rate limits** — cron-syntax jobs with full database access; per-table, per-operation throttling.
- **Admin dashboard** — every server serves a UI at `/_` with metrics, cron status, and a table browser/editor. See [Dashboard Overview](/dashboard/overview).
- **One deployable folder** — `zonai build` produces `build/` with the server binary, compiled workers, and migrations. Copy it to a server of the target OS and architecture and run `./zonai serve --release`.

## How It Works

Your Dart sources compile into **workers** — compiled programs for config, rules, operations, extensions, rate limits, and crons — that the `zonai` server calls over IPC. Each HTTP request passes through an ordered pipeline:

```text
HTTP Request
  → Rate Limit
  → Rules
  → Operations
  → SQLite
  → Extensions
  → Response
```

Nothing is interpreted at request time; all logic is compiled Dart. See [How a Request is Processed](/core-concepts/request-pipeline) and [Workers](/core-concepts/workers).

During development `zonai dev` and `zonai serve` watch your sources and recompile the affected worker when you save.

## Browse the Docs

Press <kbd>⌘</kbd><kbd>K</kbd> to search every page, or start from a section:

<SectionCards />

## What Zonai Is Not

- Not a full application framework — Zonai is an API server (no HTML rendering). Use `zonai_client` (or raw HTTP) from Flutter/Dart apps
- Not a managed cloud service — you host it yourself, anywhere that runs a macOS, Linux, or Windows binary
- Not a general-purpose ORM — it is opinionated about how APIs are structured and uses SQLite as its database

## For LLMs and coding agents

A curated docs index, starting with the minimum needed to run Zonai, lives at [/llms.txt](/llms.txt). Inside a Zonai project, run `./zonai ai` to install project-local assistant rules (Cursor, Claude, Copilot, Windsurf, Cline).
