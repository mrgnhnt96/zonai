---
title: Config Flavors
description: How to manage dev, staging, and production configurations with flavors.
---

A flavor is a named configuration variant — `dev`, `staging`, `prod`, or any name you choose. Pass it with `--flavor <name>` to `zonai serve`, `zonai dev`, `zonai compile`, and `zonai build`. One flag selects **two** things:

1. which [`AppConfig`](/configuration/app-config) file under `configPath` is compiled into the config worker, and
2. which env file (`.env.<name>`) is baked into every compiled binary.

Keep flavor names identical across the two, and use the same `--flavor` for every command in a session — `serve` recompiles with whatever flavor it was started with.

## Which config file is used

Every `.dart` file under `configPath` (default `lib/src/config`, **including subdirectories**) counts as a config file. Each must define a top-level `AppConfig main()`.

| Files under `configPath` | `--flavor` | Result |
| ------------------------ | ---------- | ------ |
| Exactly one              | ignored    | That file is always used |
| Two or more              | omitted    | Error: `Missing flavor argument, run with --flavor <flavor>` |
| Two or more              | `<name>`   | The one file whose flavor is `<name>`; an error if none or more than one match |

A file's flavor is the **last dot-separated segment of its name**, without `.dart`:

| File                   | Flavor      |
| ---------------------- | ----------- |
| `db_config.dev.dart`   | `dev`       |
| `db_config.prod.dart`  | `prod`      |
| `dev.dart`             | `dev`       |
| `db_config.dart`       | `db_config` |

There is **no fallback to a base file.** Once a second file exists, a plain `db_config.dart` is only selected by `--flavor db_config`, and a missing flavor never quietly picks it. Two practical consequences:

- Name every file `<name>.<flavor>.dart` once you have more than one environment.
- Don't keep helper `.dart` files anywhere under `configPath` — each one counts as another config file (and turns a single-file project into one that needs `--flavor`). Put shared code elsewhere in `lib/` and import it.

<Warning>

A flavor error is logged, but the config worker is not regenerated for that run — check the log for `Missing flavor argument` / `No config file found for flavor` rather than trusting the exit code.

</Warning>

## Which env file is used

| `--flavor` | File loaded   |
| ---------- | ------------- |
| omitted    | `.env`        |
| `dev`      | `.env.dev`    |
| `<name>`   | `.env.<name>` |

Exactly one file is read, from the directory you run the command in. There is **no fallback**: with `--flavor dev` and no `.env.dev`, Zonai warns `No flavor-specific .env file found for flavor: dev` and compiles with **no env defines at all** — even if `.env` exists. Every `String.fromEnvironment` then takes its `defaultValue` (an empty string when it has none), which usually surfaces as a secret-validation failure at startup. File format and CLI overrides are covered in [Environment Variables](/configuration/environment-variables).

## How secrets get baked in

Worker code reads a value with `const String.fromEnvironment('MY_SECRET')`. At compile time Zonai passes every key from the selected env file to `dart compile exe` as a `-D` define, so the binary contains the literal value — the `.env` file is not read at runtime, and editing it has no effect until you recompile.

The same defines go into every compiled binary: the config, rules, operations, extensions, rate-limit and cron workers, and the project binary. Dev and prod binaries therefore carry different secrets; never deploy a binary compiled with dev secrets. To keep the signing secrets out of the binary entirely, supply them from the process environment instead — see [Environment & Secrets](/deployment/environment-and-secrets).

## Example setup

```
my_app/
  zonai.yaml
  .env.dev              # used with --flavor dev
  .env.prod             # used with --flavor prod (keep it off shared machines)
  lib/src/config/
    db_config.dev.dart
    db_config.prod.dart
```

**`lib/src/config/db_config.dev.dart`:**

```dart in:project-file
AppConfig main() => AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
  baseUrl: 'http://localhost:8080',
  jwtExpiresIn: const Duration(hours: 1),  // short lifetime for dev
);
```

**`lib/src/config/db_config.prod.dart`:**

```dart in:project-file
AppConfig main() => AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
  baseUrl: 'https://api.myapp.com',
  email: EmailConfig(
    host: const String.fromEnvironment('SMTP_HOST'),
    port: 587,
    username: const String.fromEnvironment('SMTP_USER'),
    password: const String.fromEnvironment('SMTP_PASS'),
    from: EmailAddress(address: 'no-reply@myapp.com', name: 'My App'),
  ),
);
```

**Running with a flavor:**

```bash
# Development: db_config.dev.dart + .env.dev
zonai serve --flavor dev

# Production bundle: db_config.prod.dart + .env.prod
zonai build --flavor prod --release
```

`--flavor` and `--release` are independent: `--release` controls asserts and file watching, not which config is used. See [Building for Production](/deployment/building-for-production#release-mode).
