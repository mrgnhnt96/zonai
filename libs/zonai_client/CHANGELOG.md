## 0.1.3

- Widen the `zonai_schema` constraint to `>=0.1.0 <0.4.0` so consumers can move to `zonai_schema` 0.3.0. The published 0.1.2 declares `<0.3.0`, which excludes it — anyone using this client alongside `zonai_schema` is pinned below 0.3.0 regardless of what they ask for, and 0.3.0 is the release carrying the scheduled-cron fix. Nothing here references what changed in 0.3.0 (a `revali_core` major and new cron IPC vocabulary, both server-side), so this spans the minors rather than pinning to the newest.

## 0.1.2

- Widen the `zonai_schema` constraint to `>=0.1.0 <0.3.0` so consumers can move to `zonai_schema` 0.2.0. The published 0.1.1 declares `^0.1.0`, which excludes it — anyone using this client alongside `zonai_schema` was pinned below 0.2.0 regardless of what they asked for. Nothing here references the API that changed in 0.2.0 (`TableRateLimits.customPolicy`, which is server-side), so this deliberately spans both minors rather than pinning to the new one.
- Add `RootDataSource.logo()`, backing the optional dashboard logo served from `imagesPath`. Additive for callers; if you implement or mock `RootDataSource` yourself, you will need to add the member.

## 0.1.1

- Fix: `lib/gen/` (the generated Revali HTTP client) was excluded from the published package by the repo's root `.gitignore`, making 0.1.0 unimportable. The generated client is now tracked and shipped.

## 0.1.0

- Initial release.
