# zonai stress harness

A load-testing tool for zonai. It builds a small fixture app (`fixture/`),
boots a real compiled `zonai serve` instance from it, and drives concurrent
HTTP load against it to measure throughput and latency — and to find where
the server stops scaling.

## Usage

```sh
cd stress
dart run bin/stress.dart
```

First run compiles the `zonai` CLI itself (`-D__ZONAI_COMPILED__=true`, ~30s,
cached at `.cache/zonai_exe`), fetches the fixture's deps, generates+applies
its migration, and runs `zonai build` (~5s). Subsequent runs skip the parts
that are already done; pass `--skip-build` to also reuse the last build.

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

Auth scenarios are cheap to run separately at lower concurrency, since (see
findings below) they don't benefit from concurrency at all:

```sh
dart run bin/stress.dart --scenarios=auth-signin,auth-signup \
  --concurrency=1,5,10,20 --duration=10 --seed=0 --skip-build
```

## What the fixture looks like

`fixture/` is a minimal zonai project: an `items` table (public CRUD, no
row-level restrictions) and a `users` auth table (password auth). Its rate
limits are explicitly disabled (`lib/src/rate_limit/*.dart` return `null`
policies) — see the first finding below for why that matters.

## Findings (measured 2026-07-28, Apple M-series, single machine)

Numbers are from one run on one machine; treat them as *shape*, not SLA.
Raw data in `results/*.json`.

### 1. The default rate limit will dominate any naive load test

Every table operation defaults to **100 requests/minute per (table,
operation, client IP)** (`RateLimitPolicy.defaultPolicy`,
`libs/zonai_schema/lib/src/rate_limit/rate_limit_policy.dart`) unless a
project explicitly overrides it — there is no "unlimited" default. A single
client hammering an endpoint burns through that budget in under a second and
then gets 100% `429`s, which looks exactly like a capacity ceiling but isn't
one. The fixture disables limits (returns `null` policies) specifically so
this harness measures the server's real throughput instead. If you're
capacity-planning a real deployment, the rate limiter — not raw server
throughput — is very likely your first practical ceiling, and it's easy to
forget it's on by default.

### 2. Every DB operation round-trips through one subprocess — reads cap around 300 req/s

`GET /db/list` (read-only, no writes):

| concurrency | req/s | p50 ms | p95 ms |
|---|---|---|---|
| 1 | 153 | 6.4 | 7.9 |
| 5 | **313** | 15.6 | 19.4 |
| 10 | 309 | 31.8 | 47.5 |
| 25 | 285 | 88.9 | 144.7 |
| 50 | 268 | 190.4 | 314.7 |
| 100 | 231 | 377.9 | 745.8 |

Throughput peaks around concurrency 5 (~310 req/s) and then *falls* as
concurrency keeps rising, while latency grows roughly linearly with
concurrency — the signature of a single serial resource, not a CPU or I/O
ceiling. The cause: every `list`/`get`/`create`/`update`/`delete` call
checks table/row rules by round-tripping to the **rules worker**, which is
a single OS subprocess (`db_rules.exe`) talking newline-delimited JSON over
one stdin/stdout pipe (`apps/zonai/lib/src/db_mutator/mailman.dart`). Writes
to that pipe are serialized per-`Mailman` instance (`_sendChain`), and the
worker itself is one Dart isolate processing one line at a time. Extensions
and operations go through their own separate single-process workers the
same way. However many cores the host has, rule-gated throughput is bounded
by how fast one subprocess can pump JSON lines through one pipe — a few
hundred/sec here, regardless of concurrency or hardware.

**If you need more DB throughput:** either the worker pipeline needs actual
parallelism (a pool of rule-worker processes instead of one, or dispatching
independent requests to it concurrently instead of one live process), or
projects with simple/no rules need a fast path that skips the round trip
entirely.

### 3. Writes get *worse* under concurrency, with a hard ~5s tail

`POST /db` (create):

| concurrency | req/s | p95 ms | max ms | errors |
|---|---|---|---|---|
| 1 | **394** | 6.9 | 10.3 | 0 |
| 5 | 181 | 15.9 | 5212.5 | 4.5% |
| 10 | 142 | 32.2 | 5238.5 | 4.8% |
| 25 | 130 | 101.0 | 5272.9 | 4.3% |
| 50 | 143 | 236.4 | 5378.2 | 3.5% |
| 100 | 103 | 5536.5 | 5885.5 | 0.3% |

Unlike reads, writes never recover: 1 concurrent writer beats every higher
concurrency level tried. The `max ms` column is the giveaway — it pins at
almost exactly **5000-5900ms** at every concurrency level ≥ 5. SQLite is
opened with `PRAGMA busy_timeout = 5000` (`libs/resqlite/native/resqlite.c`),
and resqlite is single-writer; concurrent creates queue for the write lock,
and the unlucky ones ride the busy-timeout retry loop to its ceiling before
either succeeding late or failing. This is on top of the same rules-worker
round trip from finding 2, so writes pay both costs. Notably,
`libs/resqlite/experiments/088-setlk-timeout.md` shows the resqlite
maintainers already investigated exactly this class of write-contention
tail latency and rejected one candidate fix after multi-run testing — this
is a known, open problem in the storage layer, not a fixture artifact.

**Practically:** a zonai app doing more than a handful of concurrent writes
per second to the same table should expect write latency spikes into the
seconds, not milliseconds, until this is addressed upstream in resqlite.

### 4. Password hashing fully serializes and blocks the main isolate (~200ms/op, flat ~5 req/s no matter the concurrency)

`POST /auth/sign-in`:

| concurrency | req/s | p50 ms |
|---|---|---|
| 1 | 4.9 | 204.5 |
| 5 | 4.9 | 1008.1 |
| 10 | 4.9 | 2003.0 |
| 20 | 5.0 | 4200.0 |

`req/s` is flat at ~5 regardless of concurrency, and p50 scales almost
exactly linearly with it (`204ms × concurrency`) — the clearest possible
signature of full serialization with zero parallel speedup. `sign-up` shows
the same pattern. The cause: `apps/zonai/lib/src/utils/hash_password.dart`
hashes with **Argon2id** (19 MiB memory, 3 iterations — reasonable OWASP
parameters) via a synchronous, pure-Dart `Argon2BytesGenerator` call, run
directly on the request-handling isolate with no `Isolate.run`/`compute`
offload. Argon2's cost is the point of using it, but running it inline means
every sign-in/sign-up **blocks the entire event loop** for ~200ms — not just
serializing auth against itself, but plausibly stalling every other
in-flight request (list/create/etc.) on the same isolate for that window
too, since Dart isolates are single-threaded.

**Fix shape:** move the Argon2 hash/verify call into a separate isolate
(`Isolate.run` or a small persistent isolate pool) so it can't block
unrelated request handling, and so concurrent auth requests can actually
run in parallel across cores instead of queueing on one thread.

## Bug found and fixed while building this harness

`zonai build` copies migration SQL into the build output without awaiting
the write (`apps/zonai/lib/src/commands/build.dart`,
`fs.file(target)..createSync()..writeAsString(...)` — `writeAsString`
returns an unawaited `Future<File>`). The process moves on before the write
lands, so every migration file in `build/.zonai/migrations/` came out
**empty** — reproduced directly (0-byte file vs. the 130-byte source), and
it broke every compiled server in this harness with "no such table" until
fixed. Any project migration-relying deploy built with `zonai build` before
this fix would hit the same failure. Fixed by awaiting the write.
