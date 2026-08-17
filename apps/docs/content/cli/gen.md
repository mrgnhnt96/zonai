---
title: zonai gen
description: Generate a typed Dart client from the project's schema.
---

Generate a typed Dart client from the project's schema, plus `.zonai/schema.json` describing it. Your app then calls `client.posts.list(...)` and gets `PostsRow` back, instead of passing a table name as a string and parsing a `Map` by hand.

```sh
zonai gen client [flags]
```

Everything is configured by the [`client:` block in `zonai.yaml`](/configuration/zonai-yaml#client-settings). The flags below are overrides for one-off and CI use.

## Why the output directory lives outside this project

The server project **cannot** be an app dependency — `zonai_schema` pulls in native SQLite, which an app must not carry. So the generator writes into a directory the *app* owns, and `client.output` is the one genuinely required key. There is no default and there cannot be one: the destination belongs to an app this project knows nothing about.

Running the command with no `client:` block is not a silent no-op — it prints the block to add and exits non-zero.

## Flags

| Flag | Description |
|------|-------------|
| `--check` | Write nothing; exit non-zero if the committed output is stale, naming each file that differs |
| `--output <dir>` | Override `client.output` for this run |
| `--force` | Generate into a non-empty directory that has no manifest. Adds files; never deletes files zonai did not write |
| `-c, --config <path>` | Path to a custom `zonai.yaml` |
| `-h, --help` | Show help information |

## What gets written

Generated files carry a `GENERATED CODE` header and are recorded in `zonai_client_manifest.json` inside the output directory. Regeneration replaces or removes **only** the files in that manifest and touches nothing else — so the directory is safe to share with hand-written code.

Alongside the client, the command writes `.zonai/schema.json`. That file is the generator's entire input, and the artifact `--check` compares a hash against.

`--force` exists for the first run into a directory that already has files but no manifest. It is deliberately additive: zonai will not delete a file it did not write, so a mistaken `--force` cannot destroy hand-written code.

## System tables are skipped by default

Most of a registered schema is zonai's own — `_jwt`, `_rate_limit`, `_photos`, `_push_jobs`, `_log`. Any table whose name starts with `_` is a system table, and those are **left out of the generated client by default**.

The reason is specific to a *typed* client: a generated `JwtApi` or `RateLimitApi` would be discoverable and autocompleting, and types say nothing about permission — so it would read as a supported API over tables a consumer must never touch.

The skip is never silent. The command reports it:

```
Skipped 5 table(s): _jwt, _log, _photos, _push_jobs, _rate_limit
Of those, 5 are zonai's own system tables. Add one to `client.tables.include`
in zonai.yaml to generate it anyway.
```

If your project genuinely reads one — `_log` is the usual case — opt it back in by name:

```yaml
client:
  output: ../app/lib/gen/zonai
  tables:
    include: [_log]
```

`client.tables.exclude` always wins over `include`.

## Keeping the committed client honest

`--check` writes nothing and exits non-zero when the committed output no longer matches the schema:

```sh
zonai gen client --check
```

```
Generated client is stale -- 2 difference(s). Run `zonai gen client` and commit the result.
```

It names each file that differs, so you can tell whether the change was yours. On a matching tree it prints `Generated client is up to date` and exits `0`.

In CI, pass [`--no-version-check`](/cli/global-flags) alongside it, the same as the repo's other verification scripts — the pinned project version intentionally differs from the CLI under test.

## Regenerate after a schema change

The generated client is a build artifact of your schemas. Re-run it whenever a table, column, or type changes:

```sh
zonai gen client
```

```
Generated 9 file(s) for 7 table(s) in ../app/lib/gen/zonai
Wrote .zonai/schema.json (schema a59bea3e3f7b)
```

If a table disappears from the schema, its generated file is removed and named in the output.

## Using the generated client

The generated client builds on `zonai_client`, which exports the query vocabulary the generated methods take and return — `Where`, `Update`, `OrderByTerm` and friends. See [Typed Client](/dart-client/typed-client) for what the generated API looks like in application code.

## See Also

- [`client:` configuration reference](/configuration/zonai-yaml#client-settings)
- [Typed Client](/dart-client/typed-client)
- [Dart Client Overview](/dart-client/overview)
