# Flavored app configs and env files

Zonai lets you keep multiple **app configs** (secrets, branding, email settings) and **environment files** for different targets—local dev, staging, production—without duplicating the whole project. You pick a flavor at the CLI with `--flavor <name>`.

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
