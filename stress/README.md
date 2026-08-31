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
the local monorepo packages (resqlite, raindrop, zonai_schema), fetches the
fixture's deps, generates+applies its migration, and runs `zonai build`
(workers + **project-linked** `build/zonai`).
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

## Thresholds (`bin/check_thresholds.dart`, `thresholds.json`)

The harness used to produce numbers and assert nothing. It now has a gate — but a
narrower one than the obvious, and the narrowing is the point.

### What is gated: error rate. What is not: p99 latency.

Three runs on one 12-core dev machine, same build, nothing changed between them:

| metric      | median spread across the 3 runs | worst cell |
|-------------|--------------------------------|------------|
| p99 latency | **139%**                        | 2178% (`delete@50`: 19.6ms → 446.8ms) |
| error rate  | **0.00 percentage points**      | 6.97pp (`auth-signup@100`) |

25 of the 30 (scenario × concurrency) cells reported *exactly* 0.00% errors in all
three runs. Meanwhile p99 for `create@1` moved 0.65ms → 10.14ms between runs — a
1455% spread on a cell doing almost nothing.

So a p99 gate at any threshold these runs support would flap, and
`docs/testing-strategy.md` is explicit that a flapping gate gets muted and a muted
gate is worse than none. **p99 is recorded for trend and never asserted.** If you
want it gated, recalibrate first and show a spread that supports a threshold —
`thresholds.json` keeps the observed p99 per cell so that argument can be had from
data.

Run 3 was deliberately measured while the machine was under real contention (1-min
load average 76 on 12 cores, against 16 for runs 1 and 2). The error rate barely
moved. That is what makes it the trustworthy metric here, not a preference.

### Usage

```sh
dart run bin/stress.dart --json=results/nightly.json
dart run bin/check_thresholds.dart results/nightly.json
```

Exit 0 pass, 1 regression. A cell in the baseline that the run did not produce is a
**failure**, not a pass — silence where a measurement was expected is exactly the
way a gate like this goes quietly dead.

The gate is a delta against `thresholds.json`, never an absolute line: a cell fails
when its error rate exceeds its own baseline plus 2 percentage points.

### The write-queue cliff — baselined, and NOT thereby acceptable

Four cells are marked `knownBad`. They are baselined so the gate is usable today;
that is bookkeeping, not approval:

| cell            | error rate (3 runs)      |
|-----------------|--------------------------|
| `create@100`    | 97.66% / 97.72% / 97.69% |
| `delete@100`    | 98.93% / 98.73% / 99.02% |
| `mixed@100`     | 8.75% / 9.60% / 2.94%    |
| `auth-signup@100` | 7.17% / 0.20% / 1.19%  |

`create` and `delete` are clean at concurrency 50 (0.00% errors in all three runs)
and collapse at 100. That is a **cliff, not a slope**, and it reproduces to within
0.3 percentage points across runs whose load differed by 4x. The server says why —
15,480 occurrences in one run's log of:

    Request failed: Server is busy writing; retry shortly (write queue saturated).

That is deliberate backpressure doing its job, not a crash. Whether rejecting ~98%
of writes at concurrency 100 is the right size for that queue is a design question
nobody has answered, and it is the obvious next thing to measure.

Separately, and NOT the same thing, the same log carried 28 of:

    SqliteException(5): ... database is locked (code 5)

Those are a raw driver exception reaching the request path rather than clean
backpressure. 28 is small, it is not zero, and it has not been investigated.

### What this does not cover

**RSS growth is not gated.** The brief for this work asked for it and it is not
here. `bin/leak_scan.dart` measures RSS over sustained streaming load, but it is a
separate entrypoint on a different workload, and wiring it in would mean
calibrating a second baseline. Named rather than quietly dropped.

The nightly workflow (`.github/workflows/stress-nightly.yml`) runs this, but its
gate step is `continue-on-error` because **the baseline was calibrated on a dev
machine and this has never run on CI hardware.** See that file's header for how to
arm it.

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
  stress writes gitignored `pubspec_overrides.yaml` for the local monorepo
  packages (resqlite, raindrop, zonai_schema). The `revali` family is *not*
  overridden — it resolves from pub.dev, so no local revali checkout is needed.

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

**Mechanism-level repro, first attempt (WRONG — corrected below)**
(`apps/zonai/tool/stream_disconnect_repro.dart`): wraps a `StreamController`
in `.asBroadcastStream()` exactly as `BodyImpl.read()` does, serves it
through a bare `HttpServer` the way `DefaultResponseHandler` does, then
destroys the client socket abruptly mid-stream. First run reported `onCancel`
firing ~2s after the disconnect. **That result was an artifact of the test
itself**: the script called `source.close()` right before checking the
result, and explicitly closing a controller forces a paused (not cancelled)
subscription to resolve — which is a completely different code path from
disconnect-triggered cancellation. Checking the result *before* any explicit
close (the script has since been corrected) shows the true behavior:
`onCancel` never fires from the disconnect alone, even after a 10s window
with 50+ pushes. See `apps/zonai/tool/hybrid_stream_cancel_repro.dart` for
the isolated, zero-HTTP confirmation: `asBroadcastStream()`'s documented
default `onCancel` *pauses* the underlying subscription once the last
listener goes away — it does not cancel it — and a `StreamController` that's
paused this way sits there forever unless something else (like an explicit
`close()`) forces resolution. `HybridStreamEngine` never closes a live
entry's controller from outside; closing only ever happens as a
*consequence* of `onCancel` already having fired. Nothing breaks that
deadlock, so the pause is permanent. **Fix**, confirmed working in the same
repro: pass `onCancel: (sub) => sub.cancel()` to `asBroadcastStream()` in
`BodyImpl.read()` — these response-body streams are one-shot and never need
the "maybe a new listener resumes it later" semantics the default is for.
This is a `revali_router` fix (external dependency — not made here).

**Full-system measurement** (`bin/leak_scan.dart`, `--mode=build`,
1600+ stream opens per run, project-linked binary): both drop modes were run
for 4 minutes at `--streams-per-wave=30 --hold=2 --wave-interval=3`, with
every request using the *same* query (`table=items, limit=50`).

| drop mode | waves | opened | RSS start→end | RSS peak | growth |
|---|---|---|---|---|---|
| abrupt | 54 | 1609 | 75.0MB→144.3MB | 149.1MB | +69.3MB |
| graceful | 54 | 1595 | 75.1MB→144.3MB | 147.9MB | +69.2MB |

Both curves plateau rather than climb linearly, and are effectively
identical between drop modes. At the time this was read as refuting the leak
theory entirely. **That reading was incomplete, not wrong about the data**:
`HybridStreamEngine` caches one entry *per distinct query*, and every
request here used the identical `(sql, params)` — so this run only ever had
**one** entry, no matter how many abandoned subscribers piled up on it.
Leaked subscribers on a single entry are cheap (a few extra list entries and
`isClosed` checks per write) — nowhere near enough to move a ~70-150MB RSS
number. The 4-minute plateau is real; it just wasn't testing the thing that
turned out to matter.

**Confirmed leak, with real severity (2026-08-06, follow-up)**: a 15-minute
mixed-workload run (`bin/leak_scan.dart`, CRUD at `list@10/create@5/delete@5`
concurrently with stream waves mixing `/db/stream/list` (varied
`limit`/`offset`), `/db/stream` (one), and `/db/stream/count`, each keyed by
a distinct seeded row id — see `stream_scenarios.dart`'s per-request
parameter variation) collapsed: `list` p95 hit **12.9 seconds** (vs. ~3000
req/s in earlier single-scenario benchmarks), and 2168/2300 stream-open
attempts timed out. RSS itself stayed noisy/non-monotonic (59-121MB, no
clean trend) — the collapse was a latency problem, not a memory-growth one,
consistent with the mechanism below (leaked entries are cheap in RAM; the
cost is CPU, one SQL requery per live entry per write).

Isolated directly with `apps/zonai/tool/hybrid_stream_cancel_repro.dart`
(a real `HybridStreamEngine`, no compiled server needed): opening 100
distinct `/db/stream/list` connections (varied `limit`, so 100 distinct
entries) and measuring `create` latency before/after:

| condition | median create latency |
|---|---|
| baseline, no open streams | 2ms |
| 100 distinct entries alive | 84-135ms (~50x) |
| 20s after closing all 100 (~50 more writes in that window) | 87-135ms — **no recovery** |
| same test with a graceful close (`subscription.cancel()` first) instead of abrupt | same — no recovery either |

Every write to a watched table costs one SQL requery *per live entry*
watching it, unbatched (`HybridStreamEngine._flushQueue`/`_requery`). That's
fine as long as entries get removed when their client leaves — the whole
point of this investigation was checking whether they do. They don't, and
the mechanism-level repro above explains why: `asBroadcastStream()`'s
default pause-not-cancel behavior means the disconnect never reaches
`HybridStreamEngine.controller.onCancel`, so `_remove(entry)` never runs, for
*either* graceful or abrupt disconnects — confirmed identically in both the
server-level create-latency test above and the zero-HTTP mechanism repro.

**Why the two investigations don't contradict each other**: the 4-minute
plateau test only ever exercised one entry (identical query every time), so
it could never have shown this — leaked *subscribers* on one entry are
cheap; leaked *entries* (one per distinct query) are what cost a requery
each on every write. This round specifically varied query parameters to
create many distinct entries, which is what surfaced it.

**Secondary finding, root-caused and fixed (2026-08-05, follow-up):** under
this same sustained load, a small but consistent fraction of new stream
connections timed out waiting for a response entirely (11/1620 on the
abrupt run, 25/1620 on the graceful run — see `openTimeouts` in
`StreamWaveStats`, `stress/lib/src/stream_scenarios.dart`).

Root cause, confirmed with a series of throwaway diagnostics (not kept —
each just hit the fixture server directly with `dart:io`, no new harness
code): `GET /health` (no DB/rules at all) stays flat and fast (2-54ms) under
30-way concurrency; `GET /db/list` (same rules/rate-limit path as
`/db/stream/list`, but no `HybridStreamEngine`/streaming) shows the *same*
linear per-request latency ramp as the streaming endpoint did (~40ms for the
1st concurrent request up to ~750-820ms for the 30th, repeatable across
warm runs). That rules out both a harness-client artifact (the `/health`
control) and anything streaming-specific (`/db/list` alone reproduces it):
concurrent reads have no ceiling and just queue behind
`ZonaiDb`'s single rules-worker pipe (`_rules` `MailmanPool`, pool size 1 by
default — see the comment at `apps/zonai/lib/src/db_mutator/zonai_db/zonai_db.dart:98-105`)
with latency growing roughly linearly in the number of concurrent callers,
and no equivalent of the write path's `WriteBackpressureException`/503 to
fail fast once that queue gets too deep.

**Fix:** `read`/`list`/`count` now run through a new `ConcurrencyGate`
(`apps/zonai/lib/src/db_mutator/zonai_db/concurrency_gate.dart`) capping
concurrent in-flight reads at 256 (comfortably above every concurrency level
already benchmarked in this README, including the `c=100` sweeps) and
failing fast with the new `ReadBackpressureException` (HTTP 503, mapped in
`apps/zonai/lib/gen/server/routes/components/exception_catcher.dart`) past
that. Unlike the write path's queue, reads aren't serialized against each
other — the gate only bounds how many can be concurrently in flight, so
normal concurrent read throughput is unaffected. Regression-tested in
`apps/zonai/test/src/db_mutator/zonai_db/concurrency_gate_test.dart` (the
mechanism in isolation — no real DB/rules-worker needed, since the relevant
existing e2e coverage, `concurrent_list_e2e_test.dart`, was independently
found to be broken already — see below).

**Separately acknowledged, not re-investigated:** `rate_limits` rows are
*already* pruned — `DeleteOldRateLimitsCron`
(`libs/zonai_schema/lib/src/internal/crons/delete_old_rate_limits_cron.dart`)
runs every 15 minutes and deletes rows with `window_start` older than 7
days, wired into every project's cron worker unconditionally via
`InternalDbArtifacts.crons`. The `// TODO: we need a cron to clean this
every day or something` comment that used to sit above `RateLimiter` (now
removed) was stale — added in the original rate-limiting commit, before
that cron existed, and never cleaned up once it did.

**Also found, unrelated to either fix, not addressed here:**
`apps/zonai/lib/gen/server/routes/components/exception_catcher.dart` — the
hand-written exception-to-HTTP-status mapping used above — has never been
committed to git on any branch. It's currently caught by the (also
pending/uncommitted) `.gitignore` addition of `**/gen/`, which is too broad:
it ignores hand-maintained business logic living under a `gen/` directory
naming convention, not just the actually-generated files around it. Worth a
deliberate decision (narrow the ignore pattern, or relocate hand-written
components out of `gen/`) rather than a silent fix bundled into this PR.

**Fixed and verified end-to-end (2026-08-06).** The fix landed in
`revali_router` (coordinated live via the `llm_chat` cross-repo channel —
`revali`'s agent applied `onCancel: (sub) => sub.cancel()` to
`BodyImpl.read()`'s `.asBroadcastStream()` call at
`revali_router/revali_router/lib/src/body/body_impl.dart:69`, added their own
regression test tracing it through the real `async*`/`yield*` wrapper down
to `default_response_handler.dart`, and reported 281 tests passing with no
regressions). Re-ran the exact 100-distinct-entries create-latency
diagnostic against a fresh `zonai build` of the fixture (picks up the local
revali path dependency) with the fix in place:

| condition | median create latency |
|---|---|
| baseline | 1ms |
| 100 distinct entries alive | 52ms (expected — they're live, each legitimately costs a requery per write) |
| 1s after abrupt-closing all 100 | 5ms |
| 3s after | 2ms |
| 5s / 10s / 20s after | 1ms — back to baseline and **stays there** |

Before the fix this stayed pinned at 84-135ms indefinitely (confirmed out to
20s+ and 60s+ in earlier rounds). Recovery now happens within 1-3s, matching
the natural write-failure-detection timing from the mechanism repro, and
holds through the rest of the window — no relapse. **Nothing to do on the
zonai side**: the fix is entirely in the dependency; zonai just needs
whatever revali release picks this commit up.

*(Update: that release has since landed on pub.dev. The harness no longer
writes `revali*` path overrides for the fixture — the whole family resolves
from pub.dev, and no local revali checkout is required to run stress. The
measurement above is left as the historical record of how the fix was
verified at the time, against a local revali path dependency.)*

If CPU/memory monitoring for the compiled binary is wanted independently of
this (now-fixed) bug, watch CPU/latency under sustained writes (not just
RSS — this bug's footprint was always CPU, not memory) since RSS alone
stayed noisy/inconclusive even with the bug fully triggered. The `ps`-based sampler
in this harness (`lib/src/process_metrics.dart`) is a fine one-off/CI-scan
tool but isn't a substitute for real production monitoring (no `vm_service`
is wired into zonai) — that's a separate decision, not made here.

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
