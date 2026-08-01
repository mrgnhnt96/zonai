# zonai stress harness

A load-testing tool for zonai. It builds a small fixture app (`fixture/`),
boots the **project-linked** `build/zonai serve --release` binary from it, and
drives concurrent HTTP load against it to measure throughput and latency — and
to find where the server stops scaling.

## Usage

```sh
cd stress
dart run bin/stress.dart
```

First run compiles the bootstrap `zonai` CLI (`-D__ZONAI_COMPILED__=true`,
~30s, cached at `.cache/zonai_exe`), writes fixture `pubspec_overrides` for
local resqlite/revali, fetches the fixture's deps, generates+applies its
migration, and runs `zonai build` (workers + **project-linked** `build/zonai`).
Subsequent runs skip the parts that are already done; pass `--skip-build` to
also reuse the last build.

Useful flags (all optional):

| Flag | Default | Meaning |
|---|---|---|
| `--concurrency=1,10,25,50,100` | | comma list of concurrency levels to sweep |
| `--duration=5` | seconds | measured duration per concurrency level |
| `--warmup=1` | seconds | untimed warmup before each measured run |
| `--scenarios=list,create,mixed,auth-signin,auth-signup` | | which scenarios to run |
| `--seed=200` | rows | rows created before measuring (plus one auth user) |
| `--port=8099` | | port for the fixture server |
| `--skip-build` | | reuse `fixture/build/` instead of rebuilding |
| `--recompile` | | force-recompile the cached `zonai` binary |
| `--keep-server` | | leave the server running after the run for manual poking |
| `--json=path` | | write raw per-level stats as JSON |

Example — a longer CRUD-only sweep with results saved:

```sh
dart run bin/stress.dart --concurrency=1,5,10,25,50,100 --duration=8 \
  --scenarios=list,create,mixed --json=results/crud.json
```

Auth scenarios scale with concurrency now (native Argon2 + isolate
offload). Still useful to run separately so write-lock noise from signup
doesn't pollute CRUD numbers:

```sh
dart run bin/stress.dart --scenarios=auth-signin,auth-signup \
  --concurrency=1,5,10,20 --duration=10 --seed=0 --skip-build
```

To try a larger rules/ops/extensions worker pool (usually helps concurrent
*creates*, often hurts pure *list* after the batch-rules fix below):

```sh
ZONAI_WORKER_POOL_SIZE=4 dart run bin/stress.dart --skip-build \
  --scenarios=list,create --json=results/crud_pool4.json
```

## What the fixture looks like

`fixture/` is a minimal zonai project: an `items` table (public CRUD, no
row-level restrictions) and a `users` auth table (password auth). Its rate
limits are explicitly disabled (`lib/src/rate_limit/*.dart` return `null`
policies) — see the first finding below for why that matters.

## Findings (measured 2026-07-31 / Phase 2 project binary, Apple M-series)

Numbers are from one run on one machine; treat them as *shape*, not SLA.
After the project-linked binary (ops/rules in-process), create climbed past
the prior ~4.2k Mailman baseline; list stayed ~3.1k (already mostly host-side).

Example Phase 2 sweep (`--scenarios=list,create --concurrency=1,10,50`):

| scenario | concurrency | req/s |
|---|---|---|
| list | 50 | ~3143 |
| create | 10 | ~5882 |

### 1. The default rate limit will dominate any naive load test

Every table operation defaults to **100 requests/minute per (table,
operation, client IP)** unless overridden. The fixture returns `null`
policies. After the first resolve, unlimited tables also skip the
rate-limit IPC entirely.

### 2. List peak ~3.1k req/s after host-side caches + quiet request path

`GET /db/list` (limit 50) after Phase A/B:

| concurrency | req/s | p50 ms | p95 ms |
|---|---|---|---|
| 1 | 2115 | 0.4 | 0.6 |
| 5 | 3017 | 1.6 | 2.2 |
| 10 | 2922 | 3.3 | 4.3 |
| 25 | **3105** | 8.0 | 9.0 |
| 50 | 2733 | 17.2 | 23.4 |
| 100 | 2907 | 33.6 | 41.7 |

Wins: skip duplicate table-access on list→count; cache null rate-limit +
table-access + ops SQL; `requiresPerRowCheck: false` for public tables;
in-process sanitize after one metadata warm; drop `.trace`/`.request`
`_log` inserts; blacklist empty-cache. Still below Revali ping (~25k)
because each list still does real SQLite COUNT+SELECT.

`ZONAI_HTTP_WORKERS>1` currently **regresses** list (~65 req/s) — each
isolate opens its own DB/Mailman stack against one SQLite file. Keep
default `workers: 1`.

### 3. Creates: write queue removes 5s busy-timeout tails

`POST /db` after `_runWrite` serialization:

| concurrency | req/s | p95 ms | max ms | errors |
|---|---|---|---|---|
| 1 | 1322 | 1.0 | 3.8 | 0 |
| 5 | 1613 | 3.9 | 16.5 | 0 |
| 10 | 1572 | 7.7 | 132.5 | 0 |
| 25 | 1201 | 35.2 | 377.8 | 0 |
| 50 | 1587 | 36.7 | 64.4 | 0 |
| 100 | — | — | — | ~99% 503 write-backpressure |

No more `max ≈ 5000ms` through c=50. At c=100 the queue saturates and
returns **503** (`WriteBackpressureException`) instead of spinning.

### 4. Auth stays ~200 req/s (native Argon2 + `Isolate.run`)

See `results/auth_new_binary.json`.

### 5. Harness gotchas

- After Phase 2, `build/zonai` is **project-specific** — the harness no longer
  byte-compares it to the bootstrap CLI cache.
- `--no-version-check` also skips `assertVersion`.
- Fixture `sqlite3` must stay `<3.0.0` (`open.dart` removed in 3.x).
- Fixture depends on `zonai` as a path package so `project_main` can link it;
  stress writes gitignored `pubspec_overrides.yaml` for local resqlite/revali.

## Bug found and fixed while building this harness

`zonai build` copies migration SQL without awaiting the write — fixed so
`build/.zonai/migrations/` is never empty.
