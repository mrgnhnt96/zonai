# Changelog

## 0.2.0

**Custom operations work for the first time.** On 0.1.1 every request to
`PATCH /db/custom/:operation` and `/db/custom/:operation/many` returned 500,
crashing in the rate-limits worker before authorization ran ([#27]).

### Breaking

- `TableRateLimits.customPolicy` now takes `String?` instead of `String`.

  Overrides declared as `customPolicy(String operation)` no longer compile —
  Dart does not allow an override to narrow a parameter type. Widen yours to
  `String?` and handle the null case:

  ```dart
  @override
  Future<RateLimitPolicy?> customPolicy(String? operation) async {
    return switch (operation) {
      'fill' => const RateLimitPolicy(maxRequests: 20, window: Duration(minutes: 1)),
      // The host could not validate the name, so every custom operation on
      // this table shares one counter.
      null => const RateLimitPolicy(maxRequests: 60, window: Duration(minutes: 1)),
      _ => .defaultPolicy,
    };
  }
  ```

  The compile error is the intended signal: there is no working behavior on
  0.1.1 to preserve, since the path 500s.

### Fixed

- `DbRateLimits` no longer asserts `request.customOperation` non-null. The host
  passes `null` on purpose whenever it cannot validate a caller-supplied
  operation name in-process — rules running in a worker rather than linked into
  the binary — so that an unvalidated name never becomes a rate-limit bucket
  dimension a caller could rotate to land on a fresh counter. The handler threw
  on exactly that value, so the documented fallback to one coarse per-table
  bucket never degraded; it crashed. `null` now means what the caller always
  said it meant.

### Upgrading

Bump the dependency **and rebuild your workers**:

```
dart pub upgrade zonai_schema
zonai compile
```

The rate-limit check runs in `db_rate_limit.exe`, which is compiled from your
project against your resolved `zonai_schema`. A stale executable keeps the old
code, and the `.protocol` stamp will not catch it — that stamp records the IPC
framing version, which did not change here.

### A note on the CLI you're running

Custom operations need this release, but the CLI has to catch up too.

zonai CLI **0.6.2 and earlier** check the resolved `zonai_schema` against the
CLI's *own* version, on the assumption that the two ship in lockstep. They
don't — so those CLIs refuse to start on any `0.x` schema, including `0.1.1`
and this release, with *"zonai_schema … is too far behind this CLI"*. Until
the next CLI release lands, pass `--no-schema-version-check`.

The next CLI replaces that comparison with a declared floor, and this version
is that floor.

[#27]: https://github.com/mrgnhnt96/zonai/issues/27

## 0.1.1

Released 2026-08-10. No changelog was kept before 0.2.0; see the git history
under `libs/zonai_schema/` for what changed.

## 0.1.0

Initial release.
