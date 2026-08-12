# Releasing

Three artifacts ship from this repo, and they are **not** independent:

| Artifact       | Goes to  | Versioned by                    |
| -------------- | -------- | ------------------------------- |
| `zonai_schema` | pub.dev  | `libs/zonai_schema/pubspec.yaml` |
| `zonai_client` | pub.dev  | `libs/zonai_client/pubspec.yaml` |
| `zonai` (CLI)  | GitHub release | the `VERSION` file        |

## The coupling

The CLI declares a floor for `zonai_schema` — `kMinSchemaVersion`, in
`apps/zonai/lib/src/domain/schema_version/min_schema_version.dart`. Two things
follow from it, and **both** have to hold before the CLI ships:

1. **The floor must be published.** `zonai init` scaffolds
   `zonai_schema: ^<floor>` into new projects. A CLI released ahead of the
   schema it names hands people a pubspec pub cannot resolve.

2. **`zonai_client` must allow the floor — as published.** The client depends
   on `zonai_schema`. If the version of the client *on pub.dev* declares a
   constraint that excludes the floor, then anyone using both is pinned below
   it, no matter what this repo says. Widening the constraint here does nothing
   for them until the client is published.

Point 2 is the one that gets forgotten, because the repo looks correct while
consumers are stuck. It is real: `zonai_client` 0.1.1 declares
`zonai_schema: ^0.1.0`, which excludes `0.2.0`.

Neither is visible from the test suites. Every checkout here resolves
`zonai_schema` by `path:`, where the version check is a documented no-op, and
the constraints that bind consumers are the ones already on pub.dev — not the
ones in the working tree.

## The check

```
cd apps/zonai && dart run tool/verify_release_coupling.dart
```

Asks pub.dev whether a real consumer can actually reach the floor, and names
which of the two conditions is unmet. `release.yml` runs it before packaging,
so the CLI cannot go out ahead of its schema.

It is **expected to fail** between preparing a release and publishing — that is
the window it exists to describe.

It does *not* check that the floor is high enough. That is a human judgement
(see `kMinSchemaVersion`'s own docs); a floor left too low fails at the
consumer, not here.

## Order

1. **Publish `zonai_schema`.**
   Bump `libs/zonai_schema/pubspec.yaml`, add a `CHANGELOG.md` entry, then
   `cd libs/zonai_schema && dart pub publish`.

   If the release changes an API consumers implement, say so in the changelog
   with the migration — and if it changes anything a worker parses or dispatches,
   say that consumers must re-run `zonai compile`. A stale
   `.zonai/executables/*.exe` keeps the old code, and the `.protocol` stamp will
   not catch it: that stamp records the IPC *framing* version, not the message
   vocabulary.

2. **Publish `zonai_client`,** if its `zonai_schema` constraint changed — even
   when nothing else about it did. Without this step the widened constraint
   never reaches anyone.

   Prefer widening (`>=0.1.0 <0.3.0`) over bumping (`^0.2.0`) when the client
   does not touch what changed. A `^` pin drags the client's consumers onto one
   schema minor for no reason of its own.

3. **Raise `kMinSchemaVersion`** if this CLI now depends on something only the
   new schema has, and run the check above. It should pass once steps 1–2 have
   landed.

4. **Release the CLI.** Bump `VERSION`, then run the `Release` workflow.

## Raising the floor

Raise it in the same change that starts depending on newer schema — the CLI
generating code that calls an API added later, or sending an IPC message an
older schema cannot parse. `RateLimitOperation.custom` was exactly that: a
value the host sends and an old worker throws on.

Nothing enforces that pairing. The check above only asks whether the floor is
*reachable*, never whether it is *correct*.
