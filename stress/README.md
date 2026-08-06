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
| `--scenarios=list,create,delete,mixed,auth-signin,auth-signup` | | which scenarios to run |
| `--seed=200` | rows | rows created before measuring (plus one auth user) |
| `--port=8099` | | port for the fixture server |
| `--mode=build|dev` | `build` | `build`: project-linked `build/zonai serve --release`. `dev`: JIT `dart run zonai serve` (same path as day-to-day serve / what `zonai dev` attaches to). |
| `--skip-build` | | reuse `fixture/build/` (and skip worker recompile when executables exist) |
| `--recompile` | | force-recompile the cached `zonai` binary |
| `--keep-server` | | leave the server running after the run for manual poking |
| `--keep-db` | | preserve existing SQLite (default is wipe before serve for fair runs) |
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

## Leak scan (`bin/leak_scan.dart`)

A separate entrypoint (reuses this harness's fixture/build/boot plumbing via
`lib/src/harness_setup.dart`) for investigating CPU/memory behavior of a
long-running `zonai serve`, rather than throughput. Opens repeated waves of
long-lived `GET /db/stream/list` connections, holds them briefly, then drops
each wave either gracefully (cancels the client-side subscription) or
abruptly (`client.close(force: true)`, no clean HTTP close), while sampling
the server process's RSS/CPU throughout.

```sh
dart run bin/leak_scan.dart --drop=abrupt --duration=4 --mode=build
dart run bin/leak_scan.dart --drop=graceful --duration=4 --mode=build
```

| Flag | Default | Meaning |
|---|---|---|
| `--drop=graceful|abrupt` | `abrupt` | how each wave's connections are dropped |
| `--duration=3` | minutes | total run length |
| `--hold=2` | seconds | how long each wave stays open before being dropped |
| `--wave-interval=3` | seconds | time between the start of one wave and the next |
| `--streams-per-wave=20` | | concurrent connections opened per wave |
| `--sample-interval=1` | seconds | RSS/CPU sampling interval |
| `--mode=dev|build` | `dev` | same meaning as `bin/stress.dart` |
| `--port=8098` | | separate default port from `bin/stress.dart` so both can run without colliding |
| `--skip-build` / `--recompile` / `--keep-server` / `--keep-db` | | same as `bin/stress.dart` |

Writes `results/leak_scan_<mode>_<drop>.csv` (`elapsed_ms,rss_kb,cpu_percent`)
and prints a start/end/peak RSS summary with a KB/min growth rate.

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

## CPU/memory leak investigation (2026-08-05)

Started from a theory, not a reported symptom: `HybridStreamEngine`
(`apps/zonai/lib/src/db_mutator/zonai_db/resqlite/hybrid_stream_engine.dart`)
only evicts a cached live-query entry when its `StreamController.onCancel`
fires, and `/db/stream*` routes are plain chunked HTTP (`DefaultResponseHandler`
→ `BodyImpl.read()`'s `asBroadcastStream()`, no custom `onCancel`) — whose
documented default is to *pause*, not cancel, the source when the last
listener goes away. The concern: an abrupt client disconnect might never
reach `HybridStreamEngine`'s cleanup, leaking an entry (plus every
subsequent write to its watched table queuing into an orphaned controller)
forever.

**Mechanism-level repro** (`apps/zonai/tool/stream_disconnect_repro.dart`):
wraps a `StreamController` in `.asBroadcastStream()` exactly as
`BodyImpl.read()` does, serves it through a bare `HttpServer` the way
`DefaultResponseHandler` does, then destroys the client socket abruptly
mid-stream. Result: `onCancel` on the source **did** fire, ~2s after the
disconnect (once a buffered write finally failed and the cancellation
cascaded back). At this minimal, simplified level, cancellation propagates
fine.

**Full-system measurement** (`bin/leak_scan.dart`, `--mode=build`,
1600+ stream opens per run, project-linked binary): both drop modes were run
for 4 minutes at `--streams-per-wave=30 --hold=2 --wave-interval=3`.

| drop mode | waves | opened | RSS start→end | RSS peak | growth |
|---|---|---|---|---|---|
| abrupt | 54 | 1609 | 75.0MB→144.3MB | 149.1MB | +69.3MB |
| graceful | 54 | 1595 | 75.1MB→144.3MB | 147.9MB | +69.2MB |

Both curves are effectively identical, and both **plateau** rather than
climb linearly: RSS rises steadily for the first ~150-180s, then holds flat
(144-149MB) for the remainder of each 4-minute run. A real unbounded leak in
`HybridStreamEngine.onDependencyChanges`'s entry cache would keep growing for
the full run, not plateau — and if the leak were specific to *abrupt*
disconnects skipping cleanup, graceful (which unambiguously cancels the
subscription) should have stayed flat while abrupt kept climbing. Neither
happened.

**Conclusion: the leak theory is refuted, both at the mechanism level and at
full-system scale.** The ~69MB rise-then-plateau looks like a one-time
warm-up cost (heap high-water-mark settling, connection/buffer pool sizing,
or similar) common to sustained `/db/stream/list` churn regardless of how
the connection ends, not a growth pattern tied to cancellation semantics.

**Secondary finding, not chased further this round:** under this same
sustained load, a small but consistent fraction of new stream connections
timed out waiting for a response entirely (11/1620 on the abrupt run,
25/1620 on the graceful run — see `openTimeouts` in `StreamWaveStats`,
`stress/lib/src/stream_scenarios.dart`). `runStreamWaves` opens each wave's
connections with a fresh `HttpClient` per connection and a 5s timeout per
open, added specifically because an earlier version of this harness would
otherwise hang forever on one stuck request per wave (`Future.wait` waits
for *all* of a wave's opens). Whether this reflects real server-side
contention (e.g. the single-instance rules-worker Mailman serializing 30
concurrent `canList` checks) or is an artifact of the harness itself
(30 brand-new `HttpClient`s opening concurrently) wasn't distinguished here
— worth a follow-up if `/db/stream*` latency under concurrent load ever
becomes a real concern, but it's a request-latency question, not a
leak/monitoring one.

**Separately acknowledged, not re-investigated:** `rate_limits` rows are
never pruned (`apps/zonai/lib/src/services/rate_limiter.dart:12`,
`// TODO: we need a cron to clean this every day or something`). Unbounded
SQLite row growth from long-running traffic, not a Dart-heap leak — the
cause is already known and undisputed, so it didn't need repro treatment.

**Recommendation:** no fix needed for the original leak theory — it isn't
real. If CPU/memory monitoring for the compiled binary is still wanted going
forward, it should watch for genuinely unbounded growth (no plateau) rather
than assume `/db/stream*` connection churn itself is suspect. The `ps`-based
sampler in this harness (`lib/src/process_metrics.dart`) is a fine
one-off/CI-scan tool but isn't a substitute for real production monitoring
(no `vm_service` is wired into zonai) — that's a separate decision, not
made here.

## Bug found and fixed while building this harness

`zonai build` copies migration SQL without awaiting the write — fixed so
`build/.zonai/migrations/` is never empty.

While building `bin/leak_scan.dart`: spawning a fresh `ps` subprocess every
sample tick (`Process.run('ps', ...)`) from a process that's also churning
through dozens of concurrent `HttpClient` sockets is flaky — `ps` would
intermittently, then under sustained load persistently, come back with
empty output/exit 1 even though the target process was provably still alive
(confirmed by sampling the same real server with no concurrent socket load,
where every tick succeeded). Fixed by spawning one long-lived
`bash -c 'while kill -0 $pid; do ps ...; sleep ...; done'` loop up front
instead of forking a new `ps` per tick (`lib/src/process_metrics.dart`).
Separately, `runStreamWaves` (`lib/src/stream_scenarios.dart`) could hang
forever: opening a wave is one `Future.wait` over N concurrent connection
attempts, and a single request that never got a response (rather than
failing fast) blocked the entire wave — and therefore the whole scan —
indefinitely. Fixed with a 5s timeout per connection attempt, counted
separately as `openTimeouts`.
