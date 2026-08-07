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

## After updating the CLI

See [`zonai version`](/cli/version) for updating the CLI itself. After
updating, run `zonai compile` (dev) or `zonai build` (production) so workers
and the host binary are rebuilt against the same `zonai_schema`.
