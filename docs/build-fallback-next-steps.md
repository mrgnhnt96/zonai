# `zonai build` outside the monorepo — what shipped in v0.6.1, and what's left

Handoff notes for the work released as **v0.6.1** on 2026-08-11. Written to be
read cold: everything below names the file, the commit, or the run it came from.

## The problem this solved

`865ee7c` (2026-07-31) made `zonai build` *always* compile a project-linked
binary — one with the project's ops/rules statically linked in, so `ZonaiDb`
dispatches directly instead of over Mailman IPC. The generated entry
(`.dart_tool/zonai/project_main.dart`) imports `package:zonai/src/bootstrap.dart`,
which only resolves inside a package graph containing zonai itself.

**No real project has that.** zonai ships as a standalone binary and is never an
application dependency. Every other command has an escape hatch
(`ZONAI_FORCE_WORKERS`); `build` had none, so it aborted outright with
`Bad state: Generating AOT kernel dill failed!`, exit 254.

Two releases shipped that way with CI green throughout, because the only thing
running `build` in CI was a fixture that had been given a `zonai` path
dependency (`27b3273`) specifically to satisfy it — the one "project" in
existence shaped that way.

## What v0.6.1 changed

| Commit | What |
|---|---|
| `1dd6ee0` | The build fallback, the workspace-aware package-config walk, the native-library stamp, `canCompile` taking an `Arch`, and the CLI release-tag selection |
| `31e962d` | Native libraries as release assets; the `build-command` CI gate; `e2e/build_smoke` |
| `9ee09be` | `canCompile` truth-table test |
| `9d12fcc` | Version bump |
| `15737af` | Compat check pinned to the newest CLI tag |

### The decision `zonai build` now makes

`projectLinkSkipReason()` in `apps/zonai/lib/src/commands/build.dart` returns the
reason a project-linked binary is impossible, or `null`:

1. `ZONAI_FORCE_WORKERS` is set
2. `package:zonai` doesn't resolve from the project
3. *(cross-target is deliberately absent — see below)*

On any of those it logs the reason and bundles the published binary
(`versions.downloadBinary`, dead code since `865ee7c`), which drives the Mailman
workers compiled just above — the pairing every build shipped before project
linking existed.

`projectResolvesZonai()` (`project_runtime.dart`) **walks up** for
`.dart_tool/package_config.json`. A pub workspace writes exactly one config, at
the root; checking only the project directory reports every workspace member —
`apps/playground` included — as unable to link. Nearest config wins; an
ancestor's is a different resolution answering a different question.

`maybeReexecProjectRuntime` has the same guard, which is what the e2e fixtures
were working around with `ZONAI_FORCE_WORKERS=1` in `cee2a5f`.

### Cross-target native libraries

`dart compile exe --target-os` cross-compiles the executable *format* but not the
native-library bytes embedded as Dart constants — see the comment on
`resqlite_native.dart`'s `_requestFromSpawner`. So a binary cross-compiled on
macOS self-extracts a `.dylib` onto the Linux host it runs on. Workers survive
this by asking their spawner; **the host has nobody to ask**.

The fix, end to end:

- `compile.yml` uploads `native-libs-embedded-<target>` — the libraries *that
  binary embedded*, not a fresh pull from `native-libs.yml`. Sourcing both from
  "latest successful run" of two workflows would let them disagree, and since an
  on-disk library overrides the embedded copy, that mismatch fails silently at
  runtime for whoever cross-builds.
- `release.yml` packages them as `native-libs-<os>-<arch>.zip` and asserts all 11
  assets landed.
- `Versions.downloadNativeLibs` fetches the target's set into
  `build/.zonai/lib/`, writes each via temp-file + rename, and stamps it.
- `_extractCompiledLibrary` (both `resqlite_native.dart` and `argon2_native.dart`)
  keeps a stamped library only when the stamp names *this* `kVersion` and the
  running platform. Anything else — unstamped, another release, another target —
  loses to the embedded copy. Erring that way keeps the failure mode "re-extracted
  a library that was already fine".

Note `_bundleTargetNativeLibs` downloads at **`kVersion`**, not
`settings.version`: a linked binary is compiled from this CLI's source and must
pair with this release's libraries. The stock-binary fallback uses
`settings.version` and is stamped to match. They diverge under
`--no-version-check`, and a stamp that doesn't match the binary reading it just
stops applying.

### `canCompile` now takes an `Arch`

Checking only the OS let `--target-arch x64` on an Apple Silicon Mac past the
guard and fail minutes later inside `dart compile exe`. Probed against Dart 3.12
on macOS arm64 (`target_os_test.dart` records the full output): Linux from any
host, otherwise an exact host match including architecture.

### Three release-tag bugs, one root cause

`zonai_schema-v0.1.0` and `zonai_client-v0.1.0` were published on 2026-08-10 and
became newer than `v0.6.0`. GitHub's "latest" is simply the most recent
non-draft release *of any kind*, so a package release took the slot and broke
three things at once, all silently:

1. `resolve_release_version.sh` bumped the tag `zonai_schema-v0.1.0` into the
   literal string `zonai_schema-v0.2.0` and wrote it into `VERSION`/`kVersion`.
2. `verify-release.yml`'s compat check downloaded from it and got
   `no assets to download` — all five jobs, run `31443483040`.
3. Every `releases/latest/download/...` link in the docs 404'd, and the shipped
   CLI's `_fetchLatestRelease` reported "a new version of zonai_client-0.1.0".

The filter now lives in one place: **`tool/ci/latest_cli_release_tag.sh`**
(newest non-draft, non-prerelease `v<semver>`). Used by the version resolver and
the compat check; `versions.dart` has the Dart equivalent; `release.yml` passes
`--latest` explicitly.

## Verification that actually ran

- Full suite **272 tests** green; `dart analyze` clean.
- **Verify Release run `31444744628`: 15/15 jobs green**, including the new
  `build-command` gate on all five platforms. Windows log confirms the whole
  chain: correct fallback with reason logged, `zonai.exe` naming, every bundle
  assertion, and a real `/health` 200 served out of `build/`.
- **Positive control:** the gate exits **254** against a pre-fix binary. A gate
  that cannot fail proves nothing, so this was run deliberately.
- **Release run `31558446442`: success.** `v0.6.1` published with 11 assets;
  `/releases/latest` → `v0.6.1`.
- **`downloadNativeLibs` exercised against the real release:** fetched
  `native-libs-linux-arm64.zip`, wrote `libresqlite.so` + `libargon2sodium.so`
  as `ELF 64-bit LSB shared object, ARM aarch64`, mode `755`, stamps reading
  `0.6.1 linux arm64`. This is the piece that had never run before.

## What's left

### 1. `--check` only tests existence, not freshness

`libs/resqlite/tool/build_native.dart --check` exits 1 "when the library is
missing" — nothing compares against the native *sources*. The argon2 side is a
bare `[ -f ... ]` in `scripts.yaml`. So if the resqlite submodule pin moves or
`build_argon2_native.dart` changes, `compile.yml` downloads the last
`native-libs.yml` artifact, `--check` passes, and it embeds a **stale** library
— silently. Step 2 didn't cause this, but it raised the stakes: those bytes now
also ship as assets that override the embedded copy on disk.

Not currently biting — last `native-libs.yml` run 2026-08-01, last argon2 builder
change 2026-07-28, last resqlite pin move 2026-07-31, so the cache postdates both.

Options, in the order they were weighed:

- **A** — chain `native-libs.yml` into compile. Guarantees freshness; every
  compile rebuilds libsodium via autoconf, deleting the cache's whole purpose.
- **B** — make `--check` real: stamp the library with the submodule SHA + builder
  hash and compare. Closes it properly, keeps the cache. Most work, and spans the
  resqlite submodule's tooling. This is the same stamp pattern the repo already
  uses twice (`.protocol` for worker IPC, `.stamp` for native libs), so it'd be
  consistent rather than novel.
- **C** — a `fresh_native_libs` dispatch input on `compile.yml` forcing
  `ZONAI_SKIP_NATIVE_BUILD=false`. Releases always correct, dev compiles stay
  fast, a few lines. Relies on remembering to set it.

**Recommendation: C now, B when there's appetite.**

Related: `native-libs.yml` is `workflow_dispatch`-only and hasn't run since
2026-08-01. Its artifacts expire at the 90-day default (**~2026-10-30**), after
which every compile silently falls back to source builds behind a `::warning::`.

### 2. In-process ops/rules for real deployments

Since zonai can never be an application dependency, `projectResolvesZonai()` is
false in every real project — so the linked binary from `865ee7c` is unreachable
outside `apps/playground`. **The speed win has never applied to a real deploy.**

`dart compile exe --packages=<file>` is the way out, and it was proven manually:
synthesize a merged `package_config.json` from the project's and zonai's own, and
compile the project entry against it. A binary was built and run this way for a
project depending only on hosted `zonai_schema ^0.1.1` / `zonai_client ^0.1.1`,
with no `zonai` anywhere in its pubspec.

**The merge policy matters and is not symmetric:**

- *app wins on collisions* → **fails**: `Method not found: 'SQLiteDelegate'` at
  `resqlite_delegate.dart:302`. Published `zonai_schema 0.1.1` deliberately
  excludes `SQLiteDelegate` from its public barrel (issue #24), so zonai's own
  code can't compile against it. Structural, not version skew.
- *zonai wins on collisions* → **works**. Verified: binary built, ran, reported
  its version.

Requires zonai's sources on disk beside the CLI — true in override_canvas's
Docker build (it already `COPY`s the monorepo at `Dockerfile:33`), false for a
bare released binary. That limitation does not go away: when zonai's own sources
aren't there, nothing can be merged and the build falls back to workers exactly
as it does today. The point of the work is that it stops being the *only*
outcome.

#### What already exists

`apps/zonai/lib/src/domain/project/merged_package_config.dart` with 13 tests
(`test/src/domain/project/merged_package_config_test.dart`). Pure functions, no
wiring — **nothing imports it**, so it changes no behaviour until step 2 below.

```dart
MergedPackageConfig mergePackageConfigs({projectConfig, projectConfigPath, zonaiConfig, zonaiConfigPath})
MergedPackageConfig? writeMergedPackageConfig({projectConfigPath, zonaiConfigPath, outputPath})

class MergedPackageConfig { Map<String, Object?> config; List<String> overridden; }
```

Decisions already baked in, so disagreeing with one is a visible act rather than
an accident:

- **zonai wins on collisions**, for the structural reason above. A test asserts
  the direction with that reasoning in a comment.
- **Every `rootUri` is absolutised against its own config file's directory
  before merging.** This is the part that fails silently if skipped: both
  configs commonly say `../something` while sitting in different `.dart_tool`
  directories, so carrying the strings across repoints packages at directories
  that may well exist and be wrong.
- **`overridden` reports only packages whose `rootUri` actually differs.** A
  workspace project and the CLI beside it agree on most of the graph; listing
  those buries the few that matter. It exists to be logged — every entry is a
  package the app's code will be compiled against a different version of than
  pub chose for it.
- **Deterministic output**: `configVersion` 2, packages sorted, no `generated`
  timestamp (it is rewritten every build; a moving clock makes every diff look
  like a graph change).
- **Returns `null` rather than throwing** on a missing or half-written config,
  matching `projectResolvesZonai()`'s existing judgement.

#### Finding zonai's own `package_config.json` is already solved

Recorded because it was previously written up as the open design question, on
the grounds that `Platform.packageConfig` is null under AOT. It is — but
`apps/zonai/lib/src/utils/zonai_entrypoint.dart:62` already handles exactly
that: `_packageConfigCandidates()` tries `Platform.packageConfig`, then walks up
from `Directory.current`, then from `Platform.script`, and
`_entrypointFromPackageConfig` resolves zonai's package root out of whichever
config it finds and confirms `bin/zonai.dart` is really there.

So step 1 is a sibling of `zonaiSourceEntrypoint()` returning the config path
instead of the entrypoint, over the same candidates — not a new mechanism.

#### What is left

1. **`zonaiPackageConfigPath()`** in `zonai_entrypoint.dart`, reusing
   `_packageConfigCandidates()`. Returns `null` when zonai's sources aren't
   reachable, which is the bare-released-binary case.
2. **Wire it into `ProjectBinary().compile()`**: write the merged config, pass
   `--packages=<file>` to `dart compile exe`.
3. **Relax `projectLinkSkipReason()`** in `commands/build.dart`. Today it
   returns "package:zonai is not resolvable" whenever `projectResolvesZonai()`
   is false, which is every real project. It has to try the merge first and skip
   only when zonai's own config cannot be found — with the reason still named,
   since every branch there is a silent fallback to worker IPC.
4. **Log `overridden`.** It is returned for this and currently consumed by
   nothing; a version substitution that nothing mentions is the failure this
   whole document keeps running into.
5. **Decide about `maybeReexecProjectRuntime`** (`project_runtime.dart`), the
   JIT path for `serve`/`db`/`dev`. It carries the same `projectResolvesZonai()`
   guard, so it either gets the same treatment or an explicit note saying why
   not.
6. **An e2e test**: a fixture with no `zonai` dependency producing a linked
   binary that runs. `e2e/build_smoke` is already shaped for this. The manual
   proof above has never been automated, so nothing would catch this regressing
   back to workers — and it regressing is invisible by construction, because
   falling back to workers *works*.
A `verify.yaml` rule for the two files is already in place on this machine.
`.game_loop/` is gitignored, so it travels with the checkout it was written in
and not with the repo — a fresh clone has to add it again.

#### What it actually buys, and what it does not

Worth knowing before spending the time, because the honest answer is narrower
than "it makes deploys faster":

- Four call sites change. Three are dispatch (`zonai_db/parts/__utils.dart:7`
  rules, `:20` operations, `:362` extensions), each otherwise a serialise → pipe
  → subprocess → deserialise round trip per rule check and per operation. No
  measurement of that cost exists; do not quote a number that has not been
  taken.
- The fourth is behavioural, not performance: `RateLimiter`
  `isRegisteredCustomOperation` (`services/rate_limiter.dart:44`) can only
  answer when rules are linked, and returns `null` otherwise, so callers fall
  back to the coarse per-table `.custom` bucket. **Per-operation rate limiting
  has therefore never run in fine-grained mode outside `apps/playground`.** The
  rules layer still denies unregistered operations, so this is not an
  authorisation hole — but it is the strongest single argument for doing the
  work.
- It does **not** remove workers from the bundle: `build()` calls `compile()`
  unconditionally before the link/no-link branch, so a linked bundle still ships
  all six worker executables.
- It therefore does **not** retire the cross-compiled native-library failure
  class in item 4 — it moves it. A linked binary is itself cross-compiled and
  embeds the build host's libraries, which is exactly why `1dd6ee0` added the
  stamped-library fetch for that path.

### 3. The `_extractCompiledLibrary` guard has no automated test

`kIsCompiled` is a compile-time constant `false` under `dart test`, so no local
suite can reach that branch. The stamp predicate itself is unit-tested
(`native_library_stamp_test.dart`, 8 cases) and the guard was exercised by hand.
Declared as a known gap in `.game_loop/verify.yaml`. Closing it needs a
`*_compiled_e2e_test.dart` that compiles a binary, plants a stamped library, and
asserts it survives.

### 4. Cross-target deploys are now gated — what the gate does and does not prove

Reported as a deploy failure on 2026-08-11: a project cross-building on macOS
arm64 for a Fly linux/x64 machine. `downloadNativeLibs` was reachable only from
the project-linked branch, so `_bundleTargetNativeLibs` never ran for a project
that cannot link — which is every real one. `build.dart` now fetches before the
branch, unconditionally when the target isn't the host.

**A bundle without those libraries still deploys**, which is worth writing down
because it contradicts the obvious reading. Verified by removing
`build/.zonai/lib/` from a working bundle and running it: the *published* binary
is built for the target, so its own embedded libraries are correct, and workers
ask it for theirs over IPC rather than trusting their own. The fetch is the
on-disk fallback for when that ask fails — not the thing that makes a deploy
work.

What actually breaks is the ask failing: pre-guard, a cross-compiled worker then
self-extracted Mach-O over `.zonai/lib/libresqlite.so`, which is the *shared*
path every process on the machine loads from, so one worker's mistake replaced
a working library for all of them (`invalid ELF header`, reproduced under
`--platform linux/amd64`). `checkNativeLibraryPlatform`
(`domain/native_library_format.dart`) reads the object-file header and refuses.

The gate is `cross-target-build` + `cross-target-run` in `verify-release.yml`,
driving `tool/ci/cross_target_build.sh` and
`tool/ci/verify_cross_target_bundle.sh`. It has to be two jobs: building must
happen on a host that isn't the target, running must happen on the target, and
macOS runners have no container runtime. Both halves were confirmed able to
fail, against binaries compiled from the commit before the fix — the build half
exits 1 with no `.zonai/lib/libresqlite.so`, the run half catches the pre-guard
probe installing a Mach-O library into a Linux extraction path.

**Not covered, and it is the half that a deploy failure will come from next:**
nothing here runs the *application's* deploy — only `e2e/build_smoke`. Two
things from that incident were never explained by anything in this repo and
would still not be caught: the log line `Loading failed: Architecture mismatch.`
appears nowhere in zonai (Linux says `invalid ELF header`, macOS dyld says
`incompatible architecture`), so whatever prints it is app-side and is also what
decided to continue past it; and Fly release-command machines do not mount
volumes, which fits "admin row created, listed back, then not found" better than
any library problem does.

## Gotchas worth not rediscovering

- **`Verify Release` on `workflow_run` uses the *default branch's* workflow
  file.** A branch's new jobs won't appear. Dispatch explicitly with `--ref` to
  test workflow changes.
- **`release.yml` on `workflow_dispatch` downloads the *latest successful*
  compile run, with no commit filter.** Re-check which run that is immediately
  before dispatching. v0.6.1 tagged `1363133` while shipping artifacts built at
  `15737af`; the delta was docs/website only, verified before proceeding.
- **`deploy-website` / `deploy-docs` are hardcoded to `ref: main`.** Releasing
  from a branch would rebuild the sites from main and advertise the wrong
  version's download links.
- **CI checks out with `secrets.SUBMODULES_PAT`** (a personal token) with
  `submodules: recursive` across a 5-way matrix, so runs bill to the same
  5000/hr bucket as local `gh`. Two runs in quick succession exhausted it on
  2026-08-10. Read `X-RateLimit-*` response headers, not `gh api rate_limit` —
  they report different buckets and disagreed during that incident.
- **`e2e/` fixtures are not workspace members**, so the root
  `pubspec_overrides.yaml` CI writes never reaches them.
  `use_revali_git_overrides.sh` now takes an optional target dir for this.
- The `chore: release v<x>` commit is skipped when `VERSION` already matches —
  expected, not a failure.
