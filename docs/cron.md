# Cron jobs

Zonai **cron jobs** are scheduled background tasks that run on a timer while the server is up. Define them in Dart under your project’s **`cronsPath`** (default `lib/src/crons`, overridable in `zonai.yaml`). At compile time, Zonai bundles every cron file into the `db_crons` worker executable.

Cron jobs do **not** replace [rules](rules.md), [operations](operations.md), or [extensions](extensions.md). They are for periodic maintenance, cleanup, reports, and other work that should happen without an HTTP request.

## How it works

1. You run `zonai serve` (or deploy a build that includes compiled workers).
2. The server starts the `db_crons` worker and sends `StartCronsRequest`.
3. The worker registers each `CronJob` with the [`cron`](https://pub.dev/packages/cron) package and calls `run()` on the schedule.
4. Before and after each run, the worker notifies the server (`JobStarted`, `JobCompleted`, or `JobFailed`).
5. The server persists each run in the internal `_cron_jobs` SQLite table for history and catch-up logic.

```text
serve → CronMailman.start() → db_crons worker
                                    ↓
                              schedule + run()
                                    ↓
                    get / mutate / email → server (CronJwt)
                                    ↓
                         notify server → _cron_jobs rows
                                    ↓
                         queued mutate → rules → SQL → extensions
```

While `serve` is running, changes under `cronsPath` trigger a recompile so schedules stay in sync with your Dart code without restarting the database.

## Project layout

Default directory (override with `cronsPath` in `zonai.yaml`):

```text
lib/src/crons/
  cleanup_logs.dart
  purge_rate_limits.dart
```

Each `.dart` file must export a **`main()`** that returns a **`CronJob`** instance:

```dart
import 'package:cron/cron.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class CleanupLogsJob extends CronJob {
  const CleanupLogsJob()
    : super(
        name: 'cleanup_logs',
        schedule: Schedule.parse('0 3 * * *'), // every day at 03:00
      );

  @override
  Future<void> run() async {
    // Use get, mutate, email, and logger — see "Side effects" below.
  }
}

CleanupLogsJob main() => const CleanupLogsJob();
```

Only files with a `.dart` extension under `cronsPath` are included (searched recursively). Define **one cron job per file**. Each file’s `main()` must return a non-null `CronJob`. If two files use the same `name`, run history and catch-up logic are ambiguous — use a unique `name` per job.

Unlike [extensions](extensions.md), the cron worker **can compile with zero app cron files** (you get an empty scheduler and a warning). You still need a successful compile before `serve` starts the worker.

## `CronJob` API

Extend the abstract base class from `package:zonai_schema/zonai_schema.dart` (which re-exports scheduling types from `package:cron/cron.dart`).

| Property / method | Purpose                                                                                  |
| ----------------- | ---------------------------------------------------------------------------------------- |
| `name`            | Stable identifier for logging and `_cron_jobs` history (use `snake_case`)                |
| `schedule`        | When the job should run (`Schedule` from the `cron` package)                             |
| `strict`          | Whether missed runs are skipped or caught up on startup (default `true`)                 |
| `runOnStartup`    | Run once immediately when crons start, before the first scheduled tick (default `false`) |
| `enabled`         | Declared on the type; the scheduler does not skip disabled jobs yet                      |
| `run()`           | Async work for one execution; uncaught errors are logged and recorded as failed runs     |

### Schedules

Build a schedule with the `Schedule` constructor or parse standard cron text:

```dart
// Five-field cron: minute hour day month weekday
Schedule.parse('*/15 * * * *')   // every 15 minutes
Schedule.parse('0 3 * * *')        // daily at 03:00

// Or explicit fields
Schedule(minutes: [0, 30], hours: [9, 17], weekdays: [1, 2, 3, 4, 5])
```

The underlying package supports five- or six-field expressions (optional seconds). See the [`cron` package](https://pub.dev/packages/cron) for field syntax (`*`, lists, ranges, intervals).

### `strict` and catch-up

When **`strict` is `true`** (default), a job runs only on its schedule. If the server was down during a scheduled time, that tick is not replayed when the server comes back.

When **`strict` is `false`**, the worker asks the server for the last run of that `name` on startup. If a scheduled tick was missed since that run (`schedule.isDue(lastRun)`), the job runs once immediately, then continues on the normal schedule. Catch-up requires a previous row in `_cron_jobs`; the first-ever run still waits for the next scheduled time unless you use `runOnStartup`.

### `runOnStartup`

When **`runOnStartup` is `true`**, the job runs once as soon as crons start, in addition to the recurring schedule. Use this for work that must run after every deploy or server restart, not only on the clock.

`runOnStartup` and non-strict catch-up are independent: `runOnStartup` always fires on start; non-strict catch-up only runs when the schedule says a tick was missed since the last recorded run.

## Where job code runs

Cron jobs execute inside the **`db_crons` worker process**, not in HTTP handlers. Each scheduled tick wraps your `run()` method in the same worker IPC scope used by [extensions](extensions.md): reads and writes go back to the server over stdin/stdout instead of opening SQLite directly.

Overlapping runs: if a previous `run()` is still in progress when the next tick fires, the `cron` package delays the new run until the current one finishes.

## Side effects: `get`, `mutate`, and `email`

Inside `run()`, Zonai exposes the same globals as the extension worker (from `package:zonai_schema/zonai_schema.dart`):

| Global   | Purpose                                                                                |
| -------- | -------------------------------------------------------------------------------------- |
| `get`    | Read rows (`get.one`, `get.many`) with the same rules as the public API                |
| `mutate` | Queue creates, updates, or deletes (`mutate.create`, `mutate.update`, `mutate.delete`) |
| `email`  | Send custom or built-in transactional email                                            |
| `logger` | Log at debug/info/warn/error (forwarded to the server console)                         |

Every cron run acts as **`CronJwt`**: an internal worker identity with admin edit access. Rules and row rules evaluate against that JWT — design maintenance jobs so collections your crons touch allow admin deletes/updates. `CronJwt` is **not** a user session token; HTTP clients cannot present it as a bearer token (see `CronJwt` in `package:zonai_schema`).

**Reads** (`get`) run immediately and respect collection/row rules for `CronJwt`.

**Writes** (`mutate`) are **queued** during `run()` and committed when the job finishes (`JobCompleted` or `JobFailed`). Each queued mutation goes through [rules](rules.md), [operations](operations.md), and [extensions](extensions.md) the same way as extension side effects (up to 10 chained iterations).

Cron jobs do **not** invoke extension hooks for the cron tick itself — only for rows changed via `mutate`. You do not need a separate HTTP call or raw SQLite access for normal cleanup; use `get`/`mutate`/`email` unless you have a reason to bypass the API pipeline.

Example — delete rows older than 30 days:

```dart
import 'package:cron/cron.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PurgeOldLogsJob extends CronJob {
  const PurgeOldLogsJob()
    : super(
        name: 'purge_old_logs',
        schedule: Schedule.parse('0 2 * * *'),
      );

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));

    mutate.delete.many(
      tableName: 'logs',
      updates: [],
      where: Lt('created_at', cutoff),
    );

    logger.info('Queued purge of logs older than $cutoff');
  }
}

PurgeOldLogsJob main() => const PurgeOldLogsJob();
```

For SMTP setup, template files, and `email.send.*` helpers, see **[email.md](email.md)**. For compile-time env passed into the cron worker executable, see **[config-and-env-flavors.md](config-and-env-flavors.md)**.

## Run history (`_cron_jobs`)

The server maintains an internal table for auditing and catch-up:

| Column        | Meaning                                 |
| ------------- | --------------------------------------- |
| `name`        | Job `name`                              |
| `started`     | When the run began                      |
| `completed`   | Set when `run()` finished without error |
| `failed`      | Set when `run()` threw                  |
| `error`       | Error string                            |
| `stack_trace` | Stack trace string                      |

Admin-facing access follows the same rules model as other internal tables. Ordinary API clients do not manage cron history.

Server logs also emit `Cron Job started`, `Cron Job completed`, and `Cron Job failed` with the job name.

## Compilation and analysis

When crons are compiled:

1. **`dart analyze`** runs on `cronsPath`. Compilation aborts if analysis fails.
2. **`CronGenerator`** writes `.dart_tool/zonai/db_crons.dart`, importing every cron file and wiring `DbCrons(jobs: [...]).start()`.
3. **`dart compile exe`** produces `.zonai/executables/db_crons.exe` (path configurable via the Zonai data directory).

If the executable is missing at runtime, the server logs instructions to add files under `cronsPath` and run `zonai serve` or press **`c`** to recompile.

## Commands

From your app directory (where `zonai.yaml` lives):

```bash
# Compile all workers, including crons
dart run zonai compile

# Dev server: watches cronsPath, starts the cron worker, recompiles on change
dart run zonai serve
```

While `serve` is running:

- Press **`c`** to recompile all workers (config, rules, extensions, operations, rate limits, **crons**).
- Press **`p`** to ping workers, including the cron worker.

Crons start automatically when `serve` brings up the HTTP server. Stopping the server stops the worker process.

## Configuration

`zonai.yaml`:

```yaml
cronsPath: lib/src/crons
```

## Example: nightly cleanup with catch-up

A maintenance job that should run every night, and also run once if the server was offline during the scheduled window:

```dart
import 'package:cron/cron.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PurgeExpiredJwtsJob extends CronJob {
  const PurgeExpiredJwtsJob()
    : super(
        name: 'purge_expired_jwts',
        schedule: Schedule.parse('0 4 * * *'),
        strict: false,
      );

  @override
  Future<void> run() async {
    mutate.delete.many(
      tableName: 'jwts',
      updates: [],
      where: Lt('expires_at', DateTime.now()),
    );
  }
}

PurgeExpiredJwtsJob main() => const PurgeExpiredJwtsJob();
```

## See also

- **[config-and-env-flavors.md](config-and-env-flavors.md)** — worker executables and compile-time env
- **[extensions.md](extensions.md)** — event-driven hooks around HTTP mutations (not scheduled)
- **[operations.md](operations.md)** — SQL generation for API requests
- **[release-mode.md](release-mode.md)** — production builds without `--enable-asserts`
- **`libs/zonai_schema/lib/src/types/cron_job.dart`** — `CronJob` definition
- **`libs/zonai_schema/lib/src/handlers/cron/db_crons.dart`** — scheduler and startup behavior
