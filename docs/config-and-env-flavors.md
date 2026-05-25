# Flavored app configs and env files

Zonai lets you keep multiple **app configs** (secrets, branding, email settings) and **environment files** for different targets—local dev, staging, production—without duplicating the whole project. You pick a flavor at the CLI with `--flavor <name>`.

For SMTP credentials, HTML templates, and how email is sent, see **[email.md](email.md)**.

Both features are resolved from the **current working directory** when you run `dart run zonai` (typically your app root, e.g. `apps/playground`).

## App config flavors

### What counts as a config file

Dart files under your **`configPath`** (default `lib/src/config`, overridable in `zonai.yaml`) are compiled into the config worker executable. Each file must define:

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: '...',
    jwtSecret: '...',
  );
}
```

Only files with a `.dart` extension are considered.

### How the flavor name is chosen from the filename

The flavor is the **last dot-separated segment** of the file stem (basename without `.dart`):

| File                                 | Flavor           |
| ------------------------------------ | ---------------- |
| `lib/src/config/db_config.dart`      | [flavor omitted] |
| `lib/src/config/db_config.dev.dart`  | `dev`            |
| `lib/src/config/db_config.prod.dart` | `prod`           |
| `lib/src/config/dev.dart`            | [flavor omitted] |

Use either `name.<flavor>.dart` or `<flavor>.dart`; avoid ambiguous names where two files would map to the same flavor.

### Single vs multiple config files

| Situation                                   | `--flavor` required?                             |
| ------------------------------------------- | ------------------------------------------------ |
| Exactly one `.dart` file under `configPath` | No — that file is always used                    |
| Two or more `.dart` files                   | Yes — pass `--flavor` matching one file’s flavor |

If multiple files exist and `--flavor` is missing, compile fails with a message to run with `--flavor <flavor>`. If no file matches, or more than one file matches the same flavor, compile fails with an error listing the paths.

### Example layout

`zonai.yaml`:

```yaml
configPath: lib/src/config
```

`lib/src/config/db_config.dev.dart`:

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App (dev)',
    passwordSecret: 'dev-password-secret',
    jwtSecret: 'dev-jwt-secret',
  );
}
```

`lib/src/config/db_config.prod.dart`:

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
    jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  );
}
```

### Commands

From your app directory (where `zonai.yaml` lives):

```bash
# Dev flavor
dart run zonai serve --flavor dev

# Compile workers only (config, rules, extensions, operations, rate limits)
dart run zonai compile --flavor prod
```

`serve` watches `configPath` and recompiles when files change; keep the same `--flavor` for the session you intend.

## Environment files

Place `.env` files in your **app root** (same directory as `zonai.yaml`, where you run `dart run zonai`). Keys are read when Zonai compiles worker executables and passed to `dart compile exe` as compile-time defines (`-DKEY=value`).

### Which file is loaded

| `--flavor` | Files checked (in order) | Result                                                     |
| ---------- | ------------------------ | ---------------------------------------------------------- |
| omitted    | `.env` only              | Use `.env` if it exists; otherwise no env vars             |
| `dev`      | `.env.dev`, then `.env`  | Use `.env.dev` if it exists; otherwise fall back to `.env` |
| `prod`     | `.env.prod`, then `.env` | Same pattern for any flavor name                           |

If you pass `--flavor dev` but `.env.dev` is missing, Zonai logs a warning and falls back to `.env` when that file exists. If neither file exists, compilation proceeds with no env defines (unless your Dart code supplies `defaultValue` on `fromEnvironment`).

### File format

Standard `KEY=value` lines:

- Blank lines and lines starting with `#` are ignored.
- Only the **first** `=` splits key and value (values may contain `=`).
- Keys must be non-empty.

```env
# apps/playground/.env.dev
GMAIL_APP_PASSWORD=your-app-password
JWT_SECRET=local-jwt-secret
```

### Example layout

```
apps/playground/
  zonai.yaml
  .env                 # optional defaults
  .env.dev             # used with --flavor dev
  .env.prod            # used with --flavor prod
  lib/src/config/
    db_config.dev.dart
    db_config.prod.dart
```

## Baking env into worker executables

Zonai does not read `.env` at runtime inside compiled workers. Instead, when you run `serve` or `compile`, each worker is built with:

```bash
dart compile exe -DKEY1=value1,-DKEY2=value2 ... <generated-entry.dart> -o .zonai/executables/<worker>.exe
```

Every key from the selected env file becomes a **compile-time** define. In your config, rules, extensions, operations, or rate-limit Dart sources, read them with `const String.fromEnvironment('KEY')` (or `bool` / `int` variants). Values are fixed in the binary when compilation succeeds.

### Which workers receive env defines

All of these compile steps pass the same `env.dartDefineArgs` flags (omitted when no env file is loaded):

| Worker      | Source directory (default) | Output executable                      |
| ----------- | -------------------------- | -------------------------------------- |
| Config      | `lib/src/config`           | `.zonai/executables/db_config.exe`     |
| Rules       | `lib/src/rules`            | `.zonai/executables/db_rules.exe`      |
| Operations  | `lib/src/operations`       | `.zonai/executables/db_operations.exe` |
| Extensions  | `lib/src/extensions`       | `.zonai/executables/db_extensions.exe` |
| Rate limits | `lib/src/rate_limit`       |

`dart run zonai compile` builds all of them in one go. `dart run zonai serve` compiles them on startup and recompiles when watched sources change (press `c` in the serve TUI to recompile everything).

### Using env in config (example)

`lib/src/config/db_config.dart`:

```dart
email: EmailConfig(
  username: 'app@example.com',
  password: const String.fromEnvironment('GMAIL_APP_PASSWORD'),
),
```

With `apps/playground/.env` containing `GMAIL_APP_PASSWORD=...`, run:

```bash
cd apps/playground
dart run zonai compile
# or
dart run zonai serve --flavor dev
```

After compile, the password is embedded in `db_config.exe`; changing `.env` has no effect until you recompile.

### Flavor + env together

`--flavor` selects **both** the config Dart file (when multiple exist) **and** the env file (`.env.<flavor>` with `.env` fallback). Keep flavor names aligned across config filenames and env files:

```bash
dart run zonai serve --flavor dev
# → db_config.dev.dart (or matching flavor name)
# → .env.dev, else .env
```

### Production and secrets

- Pass **`--release`** when compiling or serving for production so worker executables are built without `--enable-asserts`. See **[release-mode.md](release-mode.md)**.
- Treat compiled `.zonai/executables/*.exe` as containing any secrets you passed via `-D` defines.
- Do not commit `.env` files with real credentials; add them to `.gitignore`.
- For production, prefer CI or deploy-time env injection: set variables in the environment that runs `dart run zonai compile`, or maintain a `.env.prod` only on the build host.
- Missing keys compile to empty strings unless you pass `defaultValue:` to `fromEnvironment`; validate required secrets in config `main()` if needed.
