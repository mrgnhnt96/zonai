# legacy_reclaim_redirect

Answers one question, by measuring it rather than by reading the spec:

> When the dashboard POSTs to `/dashboard/maintenance/reclaim-log-space`, does the
> request that finally reaches the **server** arrive at
> `/dashboard/maintenance/reclaim-space` **as a POST**, carrying
> `target=logdb&min_reclaimable_bytes=16777216`?

It matters because `MaintenanceController` is `POST`-only by policy — *"a `GET` that
empties a table is one prefetch away from doing it unasked"* — and
`Router._findMatch` matches on `(method, segments)`. A redirect that a client
downgrades to `GET` therefore does not reach the handler with the wrong method; it
reaches **no** handler, and 404s. The legacy route exists solely so old clients keep
working, so that failure is silent in exactly the place it is least affordable.

## What is real here and what is not

The route tree in `lib/probe_server.dart` is transcribed from what revali's codegen
emits for `MaintenanceController`
(`apps/server/.revali/server/routes/__dashboard_maintenance_route.dart`, which is
gitignored and so cannot simply be imported). Reproduced: the two paths, their
`method: 'POST'`, and the `Redirect` on the legacy one. Left out: DI, components,
argument binding, and the handler bodies — none of which participate in the
mechanism, because `RunRedirect` answers before `execute.run()` and `_findMatch`
runs before either.

So the redirect on the wire **is revali's own**, from `CannedResponse.redirect`, not
a hand-rolled one. `apps/server/test/legacy_reclaim_redirect_test.dart` asserts that
the code and target used here match both the annotation and the emitted route table,
so the transcription cannot drift silently.

The browser probe (`web/browser_probe.dart`) is the production client stack, not an
imitation of it: `RevaliClient` → `HttpPackageClient` → `http.Client()` →
`BrowserClient` → `window.fetch`, which is the same chain `apps/web` runs through
`ZonaiClient`. Only the generated `MaintenanceDataSourceImpl` wrapper above it — a
JSON decode — is missing.

The instrument is server-side: `ProbeServer` records the method and path off the raw
`HttpRequest` in its accept loop, before routing. A client can only report what it
*meant* to send, and a request that matches no route never reaches a handler that
could log it.

## Running it

```sh
dart pub get

# the dart:io leg
dart run bin/probe.dart --code 302
dart run bin/probe.dart --code 307

# the browser leg (compiles web/browser_probe.dart to JS, serves it, launches a
# browser, waits for it to post its outcome back). HEADFUL=1 to watch.
bash tool/browser_leg.sh 307 [/path/to/browser]
```

`tool/browser_leg.sh` exists because the browser leg consumes a single-consumer
resource and must run through showrunner's lock, whose argument parser swallows
leading `--flags` in the command it is handed. A script takes none:

```sh
showrunner lock run --holder <crawler> device \
  bash e2e/legacy_reclaim_redirect/tool/browser_leg.sh 307
```

## What it measured

Chrome for Testing 151.0.7922.34, headless and headed alike, both agreeing:

| redirect code | what the **server** received |
| --- | --- |
| 302 | `POST /…/reclaim-log-space` then `GET /…/reclaim-space?…` → **404** |
| 307 | `POST /…/reclaim-log-space` then `POST /…/reclaim-space?…` → **200**, both arguments intact |

`dart:io` (`package:http`'s `IOClient`) is a different answer and a worse one. Its
`HttpClientResponse.isRedirect` is false for a `POST` receiving anything but 303, so
it follows **neither 302 nor 307 nor 308** — the caller gets the raw redirect and
`RevaliClient` throws `ServerException` on it. The one code it does follow, 303, it
downgrades to `GET`, which 404s:

| redirect code | what the **server** received, driven from `dart:io` |
| --- | --- |
| 302 / 307 / 308 | `POST /…/reclaim-log-space` only — not followed |
| 303 | `POST /…/reclaim-log-space` then `GET /…/reclaim-space?…` → **404** |

No status code makes the legacy route work for a `dart:io` consumer. That is a
`dart:io` limitation rather than a property of this route, and it does not touch the
browser, which is the only caller of this path (`apps/web`'s Maintenance screen
renders the "Reclaim log space" card unconditionally, and the compiled dashboard is
the only thing in the repo that calls `reclaimLogSpace` over HTTP).

Which is why the route answers **307**, and not the 302 that was asked for.

## Not driven by `tool/ci/run_e2e.sh`

Unlike its neighbours this is not a zonai fixture project — there is no `zonai.yaml`
and nothing here is a schema. `run_e2e.sh` drives an explicit `served_fixtures` list,
so this directory is inert to it by construction. It is reached by `test static`
(which resolves and analyzes every `e2e/*/`) and by hand.
