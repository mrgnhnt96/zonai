## 0.2.1

- Widen the `zonai_schema` constraint to `>=0.1.0 <0.5.0` so consumers can move to `zonai_schema` 0.4.0. The published 0.2.0 declares `<0.4.0`, which excludes it — anyone using this client alongside `zonai_schema` is pinned below 0.4.0 regardless of what they ask for, and 0.4.0 is the release carrying push notifications and the tightened auth defaults that Zonai CLI v0.8.0 requires. Nothing here references what changed in 0.4.0 (push vocabulary and rate-limit defaults, both server-side), so this spans the minors rather than pinning to the newest.
- The generated client gains `MaintenanceDataSource` — `purgeLogs`, `purgeTable`, `cleanupPhotos` and `reclaimLogSpace`, reachable as `client.maintenance` — and `DashboardDataSource.storage()`, which back the dashboard's new Maintenance screen.
- `EmailDataSource.send`, `RootDataSource.swaggerJson` and `RootDataSource.swaggerYaml` now take an optional `authorization` argument, because the server no longer serves those unauthenticated. Additive for callers; if you implement or mock any of these interfaces yourself, you will need to add the parameter and the new members.

## 0.2.0

- **Breaking:** require `revali_client` `^3.0.0` (was `^2.1.0`). This is breaking for you only if you pass your own interceptor to `ZonaiClient(extraInterceptors: [...])`, because `HttpInterceptor.onRequest` and `onResponse` now return `FutureOr<HttpResponse?>` instead of `void`. The migration is mechanical: change the return type and `return null`, which means "carry on". Returning a response instead is the new capability — from `onRequest` it answers the call without sending anything, and from `onResponse` it substitutes what arrived, which is what makes retries, caching and circuit breaking expressible at all. Callers who pass no interceptor of their own are unaffected; this package's own X-Auth interceptor already returned `null` throughout.
- **Behaviour change, no API change:** a throwing interceptor now fails the request instead of being swallowed. Previously an interceptor that threw let the request continue in whatever half-prepared state it was left in, so a failed auth interceptor put an unauthenticated request on the wire and surfaced as a puzzling `401` from the server rather than as an error where it actually broke. If you relied on that swallowing, catch inside your interceptor.
- The bundled `revali_client` also gains `RevaliClient.timeout` and an opt-in `RetryPolicy`, and `ServerException` now parses the server's error envelope (`code`, `reason`, `details`, `isStructured`) when one was sent. This client does not yet configure any of them; they are listed because they arrive in the dependency you now resolve.
- No change to this package's own public API, generated client, or `zonai_schema` constraint. The generated client is byte-identical under `revali_client_gen` 2.5.0.

## 0.1.3

- Widen the `zonai_schema` constraint to `>=0.1.0 <0.4.0` so consumers can move to `zonai_schema` 0.3.0. The published 0.1.2 declares `<0.3.0`, which excludes it — anyone using this client alongside `zonai_schema` is pinned below 0.3.0 regardless of what they ask for, and 0.3.0 is the release carrying the scheduled-cron fix. Nothing here references what changed in 0.3.0 (a `revali_core` major and new cron IPC vocabulary, both server-side), so this spans the minors rather than pinning to the newest.

## 0.1.2

- Widen the `zonai_schema` constraint to `>=0.1.0 <0.3.0` so consumers can move to `zonai_schema` 0.2.0. The published 0.1.1 declares `^0.1.0`, which excludes it — anyone using this client alongside `zonai_schema` was pinned below 0.2.0 regardless of what they asked for. Nothing here references the API that changed in 0.2.0 (`TableRateLimits.customPolicy`, which is server-side), so this deliberately spans both minors rather than pinning to the new one.
- Add `RootDataSource.logo()`, backing the optional dashboard logo served from `imagesPath`. Additive for callers; if you implement or mock `RootDataSource` yourself, you will need to add the member.

## 0.1.1

- Fix: `lib/gen/` (the generated Revali HTTP client) was excluded from the published package by the repo's root `.gitignore`, making 0.1.0 unimportable. The generated client is now tracked and shipped.

## 0.1.0

- Initial release.
