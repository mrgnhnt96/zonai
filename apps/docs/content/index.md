---
title: Zonai
description: A batteries-included Dart backend framework — auth, database, live query streams, file uploads, cron jobs, and more.
---

Zonai is a Dart backend-as-a-service framework that turns schema definitions into a complete REST API. Write your tables, rules, and business logic in Dart — Zonai handles the HTTP layer, the database, and the auth system.

It is designed for Dart and Flutter developers who want to build a production-quality backend without wiring together boilerplate.

<CardGrid columns="3">

<Card title="Quick Start" href="/getting-started/quick-start" icon="rocket">

Go from `dart create` to a running server with auth and CRUD in about ten minutes.

</Card>

<Card title="Live Queries" href="/operations/streaming" icon="bolt" badge="live">

`client.db.listen` and `/db/stream*` push updates as SQLite data changes.

</Card>

<Card title="Dart Client" href="/dart-client/overview" icon="dart">

`zonai_client` wraps auth, db, photos and email so apps never hand-roll HTTP.

</Card>

</CardGrid>

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

Every endpoint below exists the moment that file does — no handlers, no codegen step:

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

**A full REST API for every table** — create, read, update, delete, list, count, and **live stream** endpoints are auto-handled from your schema. No HTTP handler code, no generation step needed.

**Built-in authentication** — password sign-up/sign-in, one-time passcodes, and magic links are available by mixing a single trait into an auth table. Sessions, refresh, and logout are included.

**Authorization rules** — evaluated before any SQL executes. Return `true` or `false`; a denied request gets a `403` immediately, with zero database access.

**Generated Dart client** — `zonai_client` wraps auth, admin auth, db (including `db.listen` streams), photos, and email so apps do not hand-roll HTTP.

**Transactional email via SMTP** — HTML templates with Mustache variables, sent from lifecycle hooks.

**Push notifications** — send from a lifecycle hook through FCM, or straight to APNs for iOS with no Firebase in the path. Recipients are a query over a `deviceToken` column, so a fan-out pages instead of loading every token into memory, resumes after a restart instead of re-notifying everyone, and clears the tokens the transport reports dead. See [Push Overview](/push/overview).

**Scheduled background jobs** — cron-syntax jobs compiled into a separate worker with access to the full database API.

**Per-IP rate limiting** — configurable per-table and per-operation with a simple policy class.

**Built-in admin dashboard** — every server serves a UI at `/_` with traffic metrics, cron job status, and a full table browser and editor. See [Dashboard Overview](/dashboard/overview).

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

## Browse the Docs

Press <kbd>⌘</kbd><kbd>K</kbd> to search every page, or start from a section:

<SectionCards />

## What Zonai Is Not

- Not a full application framework — Zonai is an API server (no HTML rendering). Use `zonai_client` (or raw HTTP) from Flutter/Dart apps
- Not a managed cloud service — you host it yourself, anywhere that runs a Linux/macOS/Windows binary
- Not a general-purpose ORM — it is opinionated about how APIs are structured and uses SQLite as its database

## For LLMs and coding agents

A curated docs index lives at [/llms.txt](/llms.txt). Inside a Zonai app, run `zonai ai` to install project-local assistant rules (Cursor, Claude, Copilot, etc.).

## Next Steps

- [Installation](/getting-started/installation) — prerequisites and CLI setup
- [Quick Start](/getting-started/quick-start) — create and run your first project
- [Project Structure](/getting-started/project-structure) — understand the directory layout
- [Live Queries (Streaming)](/operations/streaming) — `client.db.listen` and `/db/stream*`
