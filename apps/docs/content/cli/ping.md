---
title: zonai ping
description: Spawn each compiled worker, check that it answers, and shut it back down — without starting a server.
---

```sh
zonai ping
```

Starts each compiled worker in `.zonai/executables/`, asks it to answer, reports the result, and kills it again. **The server does not need to be running**, and nothing listens on a port.

```text
Ping extension succeeded
Ping rules succeeded
Ping operation succeeded
Ping config succeeded
Ping cron succeeded
Ping rate limit succeeded
```

Six workers are checked, in that order: extensions, rules, operations, config, crons and rate limits. Each is spawned, pinged and shut down before the next one starts, so a failure names the worker rather than leaving you to guess from a stack trace.

## What it is for

`zonai serve` compiles workers and then starts serving, which means a worker that cannot start looks like a server problem. `ping` separates the two questions: it exercises the IPC handshake — spawn, send, receive, exit — and nothing else.

Reach for it when:

- a worker was rebuilt and you want to know it runs before a request depends on it;
- `serve` fails in a way that does not say which piece is broken;
- a deploy target should be checked without exposing a port.

**Ops and rules are always pinged.** Usually requests go through those workers too; when the server is project-linked (your project depends on `package:zonai`) it calls them in-process instead, and the `.exe` files are what `ZONAI_FORCE_WORKERS=1` and this command use. See [Workers](/core-concepts/workers).

## Options

| Flag | |
|---|---|
| `-c`, `--config=<path>` | Path to `zonai.yaml`. |
| `-h`, `--help` | Show help. Prints usage and spawns nothing. |

A worker that cannot be reached prints `Ping <name> failed` and the command moves on to the next one.

**A failed ping does not change the exit code** — `ping` exits `0` whether every worker answered or none did, so it is a diagnostic to read rather than a gate to script. (`--help` exits `1`.) If you need a CI check, assert on the output.

## Related

- **[Workers](/core-concepts/workers)** — what each of these six processes does.
- **[zonai serve](/cli/serve)** — the command that compiles them and serves requests.
