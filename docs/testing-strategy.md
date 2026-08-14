# Testing zonai: a release-gating strategy

**Status:** proposal. Nothing here is implemented yet.
**Measured against:** `02cfcef` on `main`, macOS arm64, 2026-08-13. Every number below was
produced by running the thing, not by reading it.

The goal is narrow and worth stating plainly, because it is not "more tests": **no release
can ship that a machine has not proven works.** zonai already has ~250 test files and a very
good per-change local gate. What it does not have is a single command, or a single CI job,
that answers *is this releasable?* — which is why the last release was bumpy despite all
that coverage.

---

## Part 0 — What is true today

### The suites that exist, and whether they pass

| Suite | Files | Tests | Result today | Runs in CI? |
|---|---:|---:|---|---|
| `apps/zonai` (the CLI — the product) | 73 | **504** | ✅ all pass, 2m24s | ❌ never |
| `libs/zonai_schema` | 33 | **251** | ✅ all pass | ❌ never |
| `apps/web` | 18 | **145** | ✅ all pass | ❌ never |
| `apps/docs` | 2 | 19 | ❌ **1 failing** | ✅ (only suite in CI) |
| `apps/playground` | 3 | 5 | ✅ all pass | ❌ never |
| `apps/server` | 2 | 3 | ✅ all pass | ❌ never |
| `libs/resqlite` (submodule) | 17 | 172 | ❌ **117 failing** | ❌ never |
| `libs/raindrop/*` (submodule) | 100 | ? | not measured | ❌ never |
| `libs/zonai_client` | 0 | 0 | — | — |
| `libs/zonai_logger` | 0 | 0 | — | — |
| `apps/compat` | 0 | 0 | driven by `verify_compat.sh` | ✅ post-release |
| `e2e/*` (5 fixture projects) | 0 | 0 | driven indirectly | partly |
| `stress/` | 0 | 0 | manual only | ❌ never |

Two of those failures are real and neither is a product bug — which is the point:

- **`apps/docs`** — `web/search-index.json` is stale on `main` right now. The committed
  ⌘K index no longer matches `content/`. CI regenerates it before testing, so CI stays
  green while the committed artifact rots; anyone running `sip run docs start` from a clean
  checkout serves the previous revision's search index.
- **`libs/resqlite`** — 117 of 172 fail with `Resqlite native library not loaded`. The
  suite needs `dart run tool/build_native.dart` run *inside* that package first; zonai's own
  flow builds the library into `apps/zonai/lib/gen/native` instead. An undeclared
  prerequisite, not a defect — but it means nobody has run resqlite's suite in a long time.

### The five structural gaps

**1. CI runs no tests.**
Six workflows (`compile`, `native-libs`, `release`, `verify-release`, `deploy-docs`,
`deploy-website`). Exactly one `dart test` invocation exists across all of them, in
`deploy-docs.yml`, scoped to `apps/docs`. The 504-test suite covering the actual product
has never executed on CI hardware. It has certainly never executed on Windows.

**2. The release gate is inverted.**
`verify-release.yml` triggers on `workflow_run: [Compile] completed`. `release.yml` is
`workflow_dispatch:` only — its `workflow_run: [Verify Release]` trigger is **commented out**
(`release.yml:5-7`). So verification runs *beside* the release, not *before* it, and nothing
stops a human dispatching Release while Verify Release is red or has never run. The verify
matrix is genuinely good work (5 platforms, `zonai build` on each, a cross-target
build-on-macOS/run-on-Linux pair, an upgrade compat check) — it just isn't a gate.

**3. There is no repo-wide static gate, because `dart analyze .` cannot be turned on.**
At the repo root it reports **7129 issues**. 6744 errors and 296 warnings come from
`apps/web/build/` — Jaspr's compiled output, gitignored but invisible to the analyzer, which
has no `analysis_options.yaml` exclude anywhere in the tree. **Zero errors exist outside that
directory.** 25 real warnings do: 11 `libs/zonai_client`, 11 `apps/zonai`, 2
`libs/zonai_schema`, 1 in `apps/web`'s own source. Those 25 are now the recorded showrunner
baseline, not a clean bill of health.

**4. The local gate is change-scoped by design, and cannot answer the release question.**
`.game_loop/verify.yaml` is 810 lines of genuinely careful per-file rules, each with a
recorded reason. It answers *"is what I touched verified?"*. It cannot answer *"is the repo
releasable?"* — nothing sweeps the untouched. That is the correct division of labour; the
release half is simply missing.

**5. `verify.yaml`'s known-failure exemptions have gone stale, and they under-verify now.**
Five test files are downgraded to `dart analyze` on the recorded grounds that they "fail
locally for pre-existing reasons": `admin_password_update_e2e_test`,
`concurrent_list_e2e_test`, `external_auth_provisioning_e2e_test`,
`signup_backfill_e2e_test` and `build_compiled_e2e_test`.
Measured today: **`cd apps/zonai && dart test` is 504/504 green**, all four `test/e2e/*` files
and both `*_compiled_e2e_test.dart` included. Those exemptions now hide real coverage behind
`analyze`. This is exactly how a documented, reasoned, well-intentioned exemption becomes a
blind spot — nothing re-asks whether it is still true.

### There is no test entrypoint

`scripts.yaml` has `bootstrap`, `compile`, `gen` targets for everything — and no `test` key
at all. There is no `sip test`, no `tool/ci/test.sh`, nothing a new contributor or a CI job
can call. Every suite is invoked by hand, from memory, with per-package prerequisites that
live only in `verify.yaml` comments.

---

## Part 1 — The layers

Seven layers, each defined by *what it proves that the layer below cannot*. The rule
throughout: **a layer that cannot fail is not a layer.**

| | Layer | Proves | Where | Budget |
|---|---|---|---|---|
| **L0** | Static | it compiles and lints; shell + workflow syntax | every push, 1 runner | < 2 min |
| **L1** | Unit | pure logic: schema DSL, SQL builders, stamps, parsers | every push, 1 runner | < 5 min |
| **L2** | Integration | real SQLite through the real native driver, in-process | every push, 1 runner | < 5 min |
| **L3** | Compiled e2e | a **real AOT binary** doing init → migrate → serve → HTTP | every push, matrix | < 20 min |
| **L4** | Cross-platform | the same binary works on all 5 release targets | pre-release | < 40 min |
| **L5** | Upgrade / compat | v(n-1) data and projects survive v(n) | pre-release | < 15 min |
| **L6** | Load & leak | it does not degrade or leak under sustained concurrency | nightly | ~20 min |

**L2 and L3 are where zonai's bugs actually live**, and the repo's own history says so. The
release notes and `verify.yaml` record: the leading-zero `Eq` bug that a SQL-builder unit test
passed and a real driver caught (#21, closed wrongly once on the strength of the unit test);
`In`/`NotIn` values that could not cross an isolate boundary (0.3.1); a `CastList` that could
not either (0.7.1); `serve --help` starting a real server; a quote-skipping SQL dependency
parser. None of those are unit-testable in the layer that would have been cheapest. Weight
the investment accordingly — **L3 is the layer to buy first**, not L1.

---

## Part 2 — What to build, in order

### Step 1 — Make the analyzer usable *(30 min, unblocks everything)*

Add a root `analysis_options.yaml`:

```yaml
analyzer:
  exclude:
    - "**/build/**"          # Jaspr output — the 6744 phantom errors
    - "**/.dart_tool/**"
    - "**/lib/gen/**"        # generated; checked by the generator's own rule
    - "libs/raindrop/**"     # submodules analyze under their own options
    - "libs/resqlite/**"
  errors:
    todo: ignore
```

Then `dart analyze .` must exit 0 (after the 25 real warnings are fixed or explicitly
ignored). Verify by running it — a passing analyzer that excludes the interesting code is
worse than no analyzer. Cross-check the exclude list against
`find . -name '*.dart' -not -path ...` so nothing real is silently dropped.

**Then update `.showrunner/config.json`'s `analyze` check back to `dart analyze .`** — its
current explicit path list exists only to route around this, and carries the flaw that a new
package is uncovered until someone remembers to add it.

### Step 2 — One entrypoint per layer *(half a day)*

Add to `scripts.yaml`. This is the piece whose absence forces every other gap:

```yaml
test:
  (aliases): [t]
  # L0+L1+L2 — what a contributor runs before pushing. Must be < 10 min.
  (command):
    - ${{ test.static }}
    - ${{ test.unit }}
  static:
    (command):
      - dart analyze .
      - dart format --output=none --set-exit-if-changed .
      - bash tool/ci/check_shell_syntax.sh
      - bash tool/ci/check_workflows.sh
  unit:
    # Explicit list, NOT `sip test --recursive`: the recursive form would sweep the
    # submodules and the e2e fixtures, which have their own prerequisites and their
    # own owners. A suite that is skipped must be skipped out loud.
    (command):
      - cd libs/zonai_schema && dart test
      - cd libs/zonai_client && dart test
      - cd apps/server && dart test
      - cd apps/web && dart test
      - cd apps/playground && dart test
      - cd apps/docs && dart test
  cli:
    # L2+L3 — needs `sip run bootstrap test` first (lib/gen must exist).
    (command): cd apps/zonai && dart test
  e2e:
    # L3 — see step 3.
    (command): bash tool/ci/run_e2e.sh
  submodules:
    # Prerequisite-carrying, hence separate. resqlite needs its own native build.
    (command):
      - cd libs/resqlite && dart run tool/build_native.dart && dart test
      - cd libs/raindrop && dart test   # raindrop_postgres will need a service container
```

Two rules for this tree, both learned from what is already broken:

- **Every entry must state and satisfy its own prerequisites.** `test cli` is worthless
  without `bootstrap test`; `test submodules` is worthless without the native build. That is
  precisely why `libs/resqlite` is at 117 failures nobody noticed.
- **Never `--recursive`.** It sweeps fixtures and submodules into a suite nobody owns, and
  the failures get normalised.

### Step 3 — Make the e2e fixtures a real, self-checking layer *(2–3 days; the highest-value item)*

`e2e/` holds five fixture projects — `build_smoke`, `admin_password_update_repro`,
`concurrency_repro`, `external_auth`, `signup_backfill_repro`. They exist because each one
caught a real bug. Today four are driven only indirectly from inside `apps/zonai`'s suite,
and one only by a shell script in a post-release CI job.

Promote them to a first-class layer: `tool/ci/run_e2e.sh`, which for each fixture drives a
**real compiled binary** through the full product lifecycle a user actually experiences:

```
zonai init  →  db migrate generate  →  db migrate apply  →  build  →  serve
            →  HTTP assertions against the running server  →  shutdown clean
```

Assert on **HTTP responses and database contents**, not on exit codes. The recurring bug
shape in this repo — `In`/`NotIn` and `CastList` failing to cross an isolate, leading-zero
`Eq` — is invisible to anything that stops at "the command exited 0".

Add a sixth fixture, `crud_matrix`, covering every column type × every operator
(`Eq`/`In`/`NotIn`/`Like`/ranges/null-handling) over HTTP through a compiled binary. Every
one of the transport bugs above would have been caught by that single fixture, and each one
shipped instead.

### Step 4 — Wire CI: a `test.yml` that gates *(1 day)*

New workflow, on `pull_request` and `push` to `main`:

| Job | Runners | Runs |
|---|---|---|
| `static` | ubuntu | L0 — `sip run test static` |
| `unit` | ubuntu, macos, windows | L1 — `sip run test unit` |
| `cli` | ubuntu, macos, windows | L2+L3 — `bootstrap test` then `sip run test cli` |
| `e2e` | ubuntu, macos, windows | L3 — `sip run test e2e` |
| `submodules` | ubuntu | `sip run test submodules` |

Windows is the one that matters most and is hardest: it is a release target
(`zonai-windows-x64`) whose test suite has, as far as anything here records, **never run**.
Expect the first Windows run to be red on path separators, line endings and process spawning.
That redness is the finding, not an obstacle to it.

Cache: `~/.pub-cache`, and the native libraries via the existing `native-libs-cache` tag —
`bootstrap test` compiles resqlite + Argon2 from C on every runner otherwise, which alone
would blow the budget.

### Step 5 — Fix the release gate *(1 hour, largest single risk reduction)*

Three edits to `release.yml`, none of them large:

1. Add a first job that **hard-fails unless the `Test` and `Verify Release` workflows are
   green for this exact SHA.** Query the checks API for the commit; do not trust
   `workflow_run` ordering, and do not make it skippable.
2. Uncomment the `workflow_run: [Verify Release]` trigger (`release.yml:5-7`), so the happy
   path is automatic and `workflow_dispatch` becomes the deliberate override rather than the
   only door.
3. Keep `workflow_dispatch` — but have it require an explicit `force: true` input, and print
   loudly in the job summary which gates were skipped. An override that leaves no trace is
   how the next bumpy release happens.

The ordering matters more than the mechanism: **verification must precede publication.**
Today it does not.

### Step 6 — Cover the packages with nothing *(ongoing)*

- **`libs/zonai_client`** (0 tests, 11 analyzer warnings, and a memory-recorded history of a
  web-safety refactor silently dropping `ZonaiStorage` from the public export). Needs export-
  surface tests: a test that imports the public barrel and asserts every intended symbol
  resolves. That class of regression is invisible to every other layer.
- **`libs/zonai_logger`** (0 tests). Small, but `courier.dart`'s bug (#10) was *precisely* a
  logger resolving to the wrong `logger` symbol and silently no-op'ing. Assert that a scoped
  logger's sink actually receives what was written.
- **`apps/compat`** — `verify_compat.sh` is good and runs post-release. Move it pre-release.

### Step 7 — Nightly load and leak *(after the rest)*

`stress/` already builds a fixture, boots a project-linked release binary and sweeps
concurrency. It produces numbers and asserts nothing. Give it thresholds — p99 latency and
RSS growth over a sustained run — and schedule it nightly, not per-PR. Per the existing
`project_cpu_memory_monitoring_todo` note, the leak-scan harness exists and durable
monitoring does not; this is where that lands.

---

## Part 3 — Two standing rules

**Re-ask exemptions on a schedule.** Gap 5 above is the failure mode to design against: six
`verify.yaml` rules were downgraded for stated, reasonable, *then-true* reasons, and are now
hiding a suite that passes. Every known-failure exemption — in `verify.yaml`, in
`doc_snippets_baseline.txt`, in the showrunner baseline — needs a dated re-check, and the
re-check needs to be a job, not a habit.

**Prefer the gate that would have caught the last bug.** This repo's bug history is
concentrated in isolate transport, native-library loading and compiled-binary behaviour —
all of it at L2/L3. Adding unit tests is the cheap move that feels like progress and would
have caught almost none of them.

---

## Part 4 — What this plan still will not catch

Stated up front, because a strategy that claims full coverage is the most dangerous
artifact here:

- **Toolchain drift.** Every input file identical, a runner image ships a new C compiler —
  invisible to `native_build_stamp.dart` by its own admission, and invisible to all of this.
- **The `lib/gen` snapshot problem.** Both CI and showrunner worktrees consume a *generated*
  `lib/gen`. A change to a server route signature or a native binding can analyze and test
  green against a stale copy. Only regenerating in place closes it.
- **macOS x64 and linux-arm64 breadth.** The cross-target pair covers build-on-one/run-on-
  another for exactly one direction (macOS arm64 → linux x64). The other combinations are
  built and smoke-run, not tested.
- **`raindrop_postgres`.** 11 test files needing a Postgres service. Not scoped here.
- **The ~200 non-self-contained doc fences.** `doc_snippets_test.dart` covers whole-file
  examples only; fragments stay hand-maintained.
- **A new CLI command added without a `--help` guard.** `help_test.dart` enumerates by hand;
  nothing sweeps the runner's switch. Noted in `verify.yaml`, still true, still worth a
  reflective test.

---

## Sequencing summary

| | Step | Effort | Risk removed |
|---|---|---|---|
| 1 | Root `analysis_options.yaml` | 30 min | unblocks any static gate at all |
| 2 | `scripts.yaml` test entrypoints | ½ day | makes every later step expressible |
| 5 | **Release gate ordering** | 1 hr | **largest single risk reduction** |
| 4 | `test.yml` CI matrix | 1 day | first time the product is tested on CI, and on Windows |
| 3 | e2e fixtures as a real layer | 2–3 days | the layer this repo's bugs actually live in |
| 6 | Untested packages | ongoing | export-surface and logger regressions |
| 7 | Nightly load/leak | later | degradation over time |

Do 1 → 2 → 5 first. Those three are under two days together and turn "we hope it works"
into "CI says it does, and refuses to publish if it doesn't."
