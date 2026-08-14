# Revali cannot resolve a dot-shorthand annotation argument

**Rule for this repo: never write a Dart dot-shorthand (`.get`) as an argument to
an annotation that revali's server generator reads. Spell the type out
(`RateLimitOperation.get`).**

Everything below is why.

## The failure

`sip run zonai compile` died in revali server generation on the CI macOS runner:

    Failed to generate Server Construct
    Error: Invalid argument(s): The argument expression has not been resolved yet
      (`.get` (DotShorthandPropertyAccessImpl) in @QueryRateLimit<GetBody>(.get))
    Something went wrong when generating Construct revali_server

Generation aborts, so `apps/server/.revali/server/server.dart` is never written,
and the AOT step later fails on the artifact that does not exist:

    lib/src/db_mutator/revali.dart:6:8: Error: Error when reading
      'lib/gen/server/.revali/server/server.dart': No such file or directory
    Error: AOT compilation failed

The second error is downstream noise. The first one is the bug.

## Where the defect is (upstream, in revali)

`revali` 3.2.0, `lib/server/utils/annotation_argument.dart`, lines 31-41. This
is quoted verbatim from a third-party package and is a fragment of a factory
body, so it cannot compile on its own — hence `no-analyze`:

```dart no-analyze
final source = expression.toSource();
final type = expression.staticType;
final element = type?.element;

if (element == null || type == null) {
  throw ArgumentError(
    'The argument expression has not been resolved yet '
    '(${_describeExpression(expression)}'
    '${_annotationSuffix(annotationContext)})',
  );
}
```

`AnnotationArgument.fromExpression` reads `expression.staticType` off an AST it
is handed, and throws if that type is not resolved. For every other argument
form this is survivable in practice, because the source text still names
something. A dot-shorthand is the one form whose entire meaning lives in
resolution — `.get` on its own denotes nothing — so it is the first construct to
turn the latent fragility into a hard failure.

There is a second, sharper tell in the same file. `_describeExpression`
(line 153) appends ` at <line>:<col>` via `_expressionLocation` (line 160),
which returns `null` when `expression.root is! CompilationUnit`. **The CI error
carries no location suffix.** So in the failing case the annotation AST revali
received was *detached from its compilation unit* — that is, revali is reading
annotation argument ASTs that are not guaranteed to be resolved, and it does not
check before trusting `staticType`.

The same file is byte-identical in pub.dev `revali 3.2.0` and in the git `main`
commit CI pins (`08c6db9`), so this is not a version regression.

## macOS-specific, or a race?

**Neither, quite — it is the *second* codegen invocation in a job that fails.**

`.github` runs revali generation twice per e2e job: once in `Bootstrap lib/gen`
(`sip run bootstrap test`) and again in `Build zonai` (`sip run zonai compile`).
The macOS logs show the first one succeeding and the second one failing, on the
same runner, same SDK, same revali, same source:

| run | job | codegen #1 (Bootstrap) | codegen #2 (Build zonai) |
|---|---|---|---|
| 31839671048 | e2e macos-latest | ✓ 37.3s | ✗ `.get` unresolved |
| 31842392052 | e2e macos-latest | ✓ 33.1s | ✗ `.get` unresolved |
| 31846352411 | e2e macos-latest | ✗ (failed earlier) | — |
| 31830243531 | e2e macos-latest | ✓ | *no second invocation in that workflow* |
| 31839671048 | e2e ubuntu-latest | ✓ 28.6s | ✓ 8.8s |
| 31839671048 | e2e windows-latest | ✓ | ✓ |

That rules out "macOS cannot do this": macOS ran this exact generation
successfully in every run that reached it. It also rules out a pure coin-flip
race, because the outcome tracks *which invocation* it is, not chance — 2/2
first invocations passed, 2/2 second invocations failed. Note run 31830243531,
on an older workflow that invoked codegen only once: codegen passed there.

Platform still modulates it — ubuntu and windows run the identical two-invocation
sequence and pass both. So the honest statement is: **a latent unresolved-AST bug
in revali that the second invocation reliably exposes on the macOS runner and
does not expose on the others.** The mechanism that makes macOS lose is not
established.

## Not reproducible on a macOS arm64 laptop

Seven configurations were tried on macOS 15 arm64 (Darwin 25.5.0), all green:

| # | configuration | result |
|---|---|---|
| 1 | pub.dev revali 3.2.0, SDK 3.12.2, warm tree, single run | pass |
| 2 | + `raindrop vendor` immediately before codegen | pass |
| 3 | CI's exact revali git pin `08c6db97d6f2966c61328b0f495afd656762c463` | pass |
| 4 | CI's two-invocation sequence: `copy-to-cli` → `vendor` → `copy-to-cli` | pass |
| 5 | Dart SDK 3.12.0 arm64 (CI's exact version), pass 1 | pass |
| 6 | Dart SDK 3.12.0 arm64, pass 2 in the same tree | pass |
| 7 | cold tree (`rm -rf apps/server/.revali .dart_tool`), two passes | pass |

So the eliminated variables are: revali version, Dart SDK patch version, the
raindrop vendor step, warm-vs-cold analyzer state, and the number of
invocations. What remains unexplained is the CI macOS runner environment itself.
If you pick this up again, that is where to look — and the cheap next step is a
CI-side experiment, not another local one.

## What this repo did about it

Sidestepped it. All 18 dot-shorthand annotation arguments in `apps/server` were
rewritten to the explicit `RateLimitOperation.x` form:

- `apps/server/routes/controllers/db_controller.dart` — 12 sites
- `apps/server/routes/controllers/auth_controller.dart` — 6 sites

`db_controller.dart` gained `import 'package:zonai_schema/zonai_schema.dart'
show RateLimitOperation;` — it previously imported only `payloads.dart`, which
does not export the enum. That import pulls in nothing new at runtime: the rate
limit components it already imports depend on `zonai_schema.dart` anyway.

The three component classes' own doc comments already prescribed the explicit
form (`/// Annotate with @QueryRateLimit<GetBody>(RateLimitOperation.get) etc.`)
— the controllers had simply drifted away from it.

This is a workaround, not a fix. The upstream defect is still live: any
dot-shorthand in an annotation revali reads will fail the same way, in this repo
or any other. The fix belongs in
`revali/lib/server/utils/annotation_argument.dart`, which should either resolve
the annotation AST before reading `staticType` or fall back to the declared
parameter type instead of throwing.

## Guard

Nothing mechanical stops the shorthand from coming back. A `! `-prefixed comment
sits above the annotations in both controllers, and that is all — a reviewer
reading `RateLimitOperation.get` and "simplifying" it to `.get` would break the
macOS e2e job and nothing local would catch it. A lint or a grep check in the
static job would be the real guard.
