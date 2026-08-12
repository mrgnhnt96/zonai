---
title: Upgrading Zonai
description: Keeping the host binary and worker executables in sync after an upgrade.
---

## The host/worker IPC protocol

The host process (`zonai serve`, or the compiled project binary in
production) talks to worker executables (config, operations, extensions,
rules, rate limits, crons) over a framed binary protocol on stdin/stdout.
Both sides must agree on that wire format.

`zonai compile` recompiles workers only. The host/project binary is only
rebuilt by `zonai build` (or implicitly by `zonai serve --release` in dev).
If the wire protocol changes between when the host binary was last built and
when a worker is recompiled, the host and that worker no longer agree on how
to talk to each other.

## Protocol mismatch error

If you see an error like:

```
CONFIG worker (...) speaks IPC protocol vX but this host speaks vY.
```

it means the host binary and a worker executable were compiled at different
times across a wire-format change. Fix it:

```sh
zonai compile
```

`zonai compile` detects a stale dev host binary (`.zonai/zonai`) and
rebuilds it automatically as part of every run — this is the right fix for
normal day-to-day development, and it's why this should be rare.

If the host you're running is a **deployed `zonai build` bundle** rather
than a dev checkout, `zonai compile` won't help — it never touches
`build/zonai`. Rebuild and redeploy instead:

```sh
zonai build
```

This case comes up when a **long-running, already-started** production
`zonai serve` process has workers recompiled underneath it — that process
can't rebuild itself while it's running, so it fails loudly instead of
accepting a worker it can't actually talk to. Rebuild with `zonai build`,
redeploy, and restart the process.

## Message contract mismatch error

The wire format is only half of what the two sides have to agree on. The
other half is the *vocabulary* inside it — the enum values, request fields
and payload keys defined by `zonai_schema`. Those change far more often than
the framing does, and a worker compiled before such a change starts up
perfectly happily and then fails part-way through a request.

Each worker is therefore stamped with a fingerprint of the `zonai_schema`
sources it was compiled against, and the host refuses to spawn one whose
fingerprint disagrees with its own:

```
RATE_LIMITS worker (...) was built against message contract abc123def456
but this host speaks 0f9e8d7c6b5a.
```

The fix is the same as for a protocol mismatch:

```sh
zonai compile
```

and `zonai build` + redeploy if the host is a deployed bundle.

This is the expected error after upgrading `zonai_schema` without rebuilding
workers, after pulling a newer CLI, or after restoring an older
`.zonai/executables/` directory. Editing `zonai_schema` sources in a local
checkout does it too — though comment and formatting changes are excluded, so
only edits that could actually change a message count.

A worker with **no** fingerprint is allowed through: an executable built
before this stamping existed, or compiled outside `zonai compile`/`zonai
build`, is unknown rather than wrong. Run `zonai compile` to give it one.

### The same warning, without the refusal

Operations and rules can also run inside the host process, from an AOT
snapshot (`db_operations.aot`, `db_rules.aot`), which is faster than talking
to the `.exe` over a pipe. A snapshot whose fingerprint disagrees is skipped
rather than refused:

```
[OPERATIONS_EXE] .zonai/executables/db_operations.aot was built against
message contract abc123def456 but this host speaks 0f9e8d7c6b5a -- ignoring
it and using the worker process instead (dispatch still works, in-process
does not). Run `zonai compile` to refresh it, ...
```

Everything keeps working; you lose in-process dispatch until you rebuild. If
the `.exe` beside it is stale too, you get the refusal above instead.

## After updating the CLI

See [`zonai version`](/cli/version) for updating the CLI itself. After
updating, run `zonai compile` (dev) or `zonai build` (production) so workers
and the host binary are rebuilt against the same `zonai_schema`.
