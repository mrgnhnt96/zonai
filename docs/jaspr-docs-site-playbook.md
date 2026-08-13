# Playbook: turning a Jaspr Content site into a navigable, searchable docs site

Written after doing exactly this to `apps/docs` in `mrgnhnt96/zonai`. It is
addressed to an agent doing the same to a different `jaspr_content` site.

Everything here was verified against a real build and a real browser. Where a
step exists because something failed, the failure is stated — those are the
parts you cannot infer from the docs of either package.

**Companion documents**

- [`jaspr-docs-site-reference.md`](./jaspr-docs-site-reference.md) — the exact
  files, APIs and gotchas, with copy-able code.
- [`jaspr-docs-site-deployment.md`](./jaspr-docs-site-deployment.md) — publishing
  to a custom domain on GitHub Pages, including the one-domain-per-repo trap.

---

## 0. What the starting point looked like

A `jaspr_content` `ContentApp` in static mode: 77 markdown pages under
`content/`, a `DocsLayout`, and a hand-written `Sidebar` in `main.server.dart`.

The complaint was "long and tough to navigate, and there's no search."

Diagnosis before touching anything:

| Symptom | Actual cause |
| --- | --- |
| Sidebar is a wall of links | `jaspr_content`'s `Sidebar` renders every group expanded. 17 groups × 77 links, no collapsing, no landmarks. |
| Hard to find anything | No search, and no way to add it — the site is static, so there is no backend to query. |
| One page unreachable | `deployment/fly-io.md`, the longest page on the site, was in no sidebar group. Nothing detects that. |
| Duplicate emphasis | `/operations/streaming` was listed in four different groups, which reads as noise rather than importance. |
| Callouts rendering as source | `**bold**`, backticks and `[links](/urls)` appearing literally inside `<Info>` blocks on 31 pages. See §4. |

Two of those five were invisible from the markdown alone. **Build the site and
read the generated HTML before you plan anything** — `grep -o '<div class="callout' -A5 build/jaspr/index.html`
is how the callout bug surfaced.

---

## 1. Make navigation a data structure, not markup

The single highest-leverage change. Put the whole information architecture in
one file — `lib/src/navigation.dart` — and derive everything from it:

- the sidebar groups and links
- the breadcrumb
- the previous/next links at the foot of each page
- the section cards on the landing page
- the section label on each search result
- **a build-time check that every page under `content/` is listed**

That last one is the point. Before, adding a page and forgetting the sidebar
produced an unreachable page and no error. Now it fails the build.

```dart no-analyze
final class NavItem {
  const NavItem(this.title, this.href, {this.summary, this.badge});
  final String title;      // sidebar label — keep short, the column is ~17rem
  final String href;       // root-absolute, e.g. /operations/streaming
  final String? summary;   // one line, used on cards and in search results
  final String? badge;     // e.g. 'live'
}

final class NavGroup {
  const NavGroup(this.title, {required this.icon, required this.items, this.summary});
  final String title;
  final String icon;       // inline SVG string
  final String? summary;
  final List<NavItem> items;
}

const List<NavGroup> navigation = [ /* ordered as a reading path */ ];

/// Pages intentionally outside the sidebar. Anything not here and not in
/// [navigation] is a build failure.
const Set<String> unlistedRoutes = {'/about'};
```

Order the groups as a **reading path**: someone starting at the top and working
down should never hit a page that depends on one below it. That ordering is
also what makes prev/next meaningful for free.

### Regrouping

Merge related groups rather than preserving the original taxonomy. Ours went
17 → 14 by merging Schemas + Database into "Data Modeling" and Operations + API
into "Querying Data", and by removing the three duplicate streaming links.

**Do not move or rename the markdown files.** Regroup in `navigation.dart`
only. Every existing URL, inbound link, and `llms.txt` entry keeps working, and
the diff stays reviewable. Sidebar labels and page titles are allowed to differ
— shorten the label to fit the column, keep the real title for the `<h1>` and
for search results.

---

## 2. Collapse the sidebar with `<details>`, not JavaScript

Replace `jaspr_content`'s `Sidebar` with your own component built on
`<details>`/`<summary>`, and mark the group containing the current route `open`:

```dart no-analyze
details(
  classes: 'docs-sidebar-group',
  open: identical(group, activeGroup) ||
        (activeGroup == null && identical(group, navigation.first)),
  [summary(...), ul(...)],
)
```

`<details>` collapses without JavaScript, works before hydration, and is
keyboard- and screen-reader-navigable for free. A 77-link wall becomes a
14-line menu that auto-expands to where you are.

`context.page.url` gives you the current route inside the component.

Style `summary` with `list-style: none` **and** `&::-webkit-details-marker
{ display: none }` to drop the default triangle, then rotate your own chevron
on `&[open]`.

---

## 3. Search on a static site

No backend, so: generate an index at build time, ship it as a JSON file, score
it in the browser.

**Generator** (`tool/build_search_index.dart`) walks `content/`, splits each
page on its `##`/`###` headings, and emits one record per section:

```json
{"u": "/operations/streaming", "t": "Streaming (Live Queries)",
 "d": "…", "g": "Querying Data",
 "s": [{"h": "Endpoints", "a": "endpoints", "b": "…body text…"}]}
```

77 pages → 486 sections → 235 KB raw, ~65 KB gzipped. Fetched lazily on first
open, so readers who never search pay nothing.

Four things that are easy to get wrong:

1. **Anchors must match what `package:markdown` actually generates**, or every
   result deep-links to nothing. It hashes the *raw* inline text, before
   backticks and links are parsed, so `## Prefer \`zonai_client\`` becomes
   `prefer-zonai_client`, not `prefer`. Reproduce it exactly:

   ```dart no-analyze
   rawHeading.toLowerCase().trim()
       .replaceAll(RegExp('[^a-z0-9 _-]'), '')
       .replaceAll(RegExp(r'\s'), '-');
   ```

   Then **test it against the built HTML** rather than trusting the
   reimplementation — see §6.

2. **Do not strip underscores** when reducing markdown to prose. A naive
   ``replaceAll(RegExp(r'[`*_#]'), '')`` turns `zonai_client` into
   `zonaiclient` and `order_by` into `orderby` — exactly the identifiers people
   search for.

3. **Keep code block contents**, minus the fence markers. `db.listen` and
   `StreamListBody` only appear in code.

4. **Skip `#` lines inside fenced blocks** — they are shell comments, not
   headings.

**Ranking.** Every token must match somewhere in a section (AND, not OR); with
hundreds of sections, OR turns a two-word query into noise. Score title matches
far above body matches, add a whole-phrase bonus, and give the page's intro
section (no heading) a bonus so it wins ties against its own subsections.

Without the phrase bonus, `rate limit` ranked a deep `AuthTableRateLimits`
heading above the Rate Limiting overview: per-token scores alone cannot
distinguish a page *about* a topic from one that mentions it.

Cap results per page (3) and overall (24), so one long page cannot crowd out
everything else.

**Put the ranking in its own file** (`lib/src/search_index.dart`), separate from
the UI component. It is the part worth testing, and a widget cannot be unit
tested nearly as cheaply.

**Commit the generated index** so a clean checkout can `jaspr serve` with no
generation step, and add a `--check` mode plus a test that fails when it goes
stale. Regenerate it in CI anyway — a deploy should never ship a stale index
even if someone bypassed the test.

---

## 4. Fix the callout bug (you probably have it too)

`package:markdown` treats an HTML block as literal text until a blank line. So
this — the obvious way to write it, and what was on 31 of our pages —

```md
<Info>
**Live UI does not need polling.** See [Streaming](/operations/streaming).
</Info>
```

renders the asterisks and the link syntax as visible characters. The fix is
blank lines inside the tags:

```md
<Info>

**Live UI does not need polling.** See [Streaming](/operations/streaming).

</Info>
```

`jaspr_content`'s `buildNodes` maintains its element stack across markdown
nodes, so an unclosed `<Info>` correctly adopts the following paragraphs as
children.

Check your own site before assuming you are clean:

```sh
grep -rn -A1 '^<\(Info\|Warning\|Error\|Success\)>$' content/ | grep -v -- '--$'
```

The same rule applies to any custom component you add — document it, because
the failure is silent and looks like a content mistake.

---

## 5. Landing page and cards

Add `CustomComponent`s so markdown authors get cards without writing HTML:

- `<CardGrid columns="3">` — responsive grid wrapper
- `<Card title href icon badge>` — linked tile
- `<SectionCards />` — one card per `NavGroup`, **generated from
  `navigation.dart`**, so the landing page's section index cannot drift from
  the sidebar

Keep every sentence of the existing landing page. Restructure around it: cards
at the top for the three things most people want, a short "write X, get Y" code
sample that shows the framework's actual value, then the original prose, then
the generated section grid.

---

## 6. Test the things that silently rot

Nineteen tests, all against real artifacts rather than fixtures:

**`test/navigation_test.dart`**
- every sidebar link resolves to a file under `content/`
- every file under `content/` is reachable (or explicitly unlisted)
- no page listed twice
- walking `next` from the first page visits every page in order

**`test/search_index_test.dart`**
- the committed index is current with `content/` (shells out to `--check`)
- known queries rank the right page first — `listen` → the streaming page,
  `rate limit` → the rate-limiting overview
- every token must match (`streaming kubernetes` returns nothing)
- identifiers survive markdown stripping (`zonai_client`, `db.listen`, `order_by`)
- **every anchor in the index exists as an `id=` in the built HTML**

That last test is the one that earns its keep: it validates a hand-rolled
reimplementation of someone else's slug algorithm against 486 real headings. It
skips when `build/jaspr/` is absent, so run it *after* the build in CI.

---

## 7. Verify in a browser, because the DOM lies

**This is the part not to skip.** DOM assertions said search worked — dialog
present, 24 results, correct hrefs. A screenshot showed the panel was **2
pixels tall**.

Two bugs, both invisible to `querySelector` checks:

### `backdrop-filter` on an ancestor breaks `position: fixed`

`DocsLayout`'s `.header-container` sets `backdrop-filter: blur(8px)`. Any
ancestor with `transform`, `filter`, `backdrop-filter`, `will-change` or
`contain` becomes the **containing block** for `position: fixed` descendants.
A search trigger rendered into the header therefore cannot open a
viewport-covering fixed overlay — it gets sized to the header.

The fix is a modal `<dialog>` + `showModal()`, which puts the element in the
browser's **top layer**, where it is viewport-relative regardless of ancestor
filters. You also get `::backdrop`, focus trapping and Esc for free.

### Jaspr reconciles the `open` attribute back off

`showModal()` sets the `open` attribute. Jaspr's `dialog(open: false)` — the
default — removes it again on the *next* `setState`, silently closing the
dialog. Because the index loads asynchronously, that rebuild always came.

Track it in state:

```dart no-analyze
bool _open = false;   // should the dialog be rendered at all
bool _shown = false;  // has showModal() promoted it to the top layer
```

Render `dialog(open: _shown, …)`. First frame renders with the attribute absent
(`showModal()` throws `InvalidStateError` if `open` is already set), then the
post-frame callback calls `showModal()` and sets `_shown = true` so every
subsequent render keeps the attribute.

### Other things the browser caught

- **`addPostFrameCallback`, not `Future.microtask`** — the element does not
  exist in the DOM until the frame is flushed. Use
  `context.binding.addPostFrameCallback`.
- **`GlobalNodeKey.currentNode` returns null** for `universal_web` element
  types under dart2js; its type test does not survive extension-type erasure.
  Look elements up by `id` instead.
- **`dart:js_interop` breaks the server build.** A `@client` component rendered
  in the header is compiled for the server too. Import
  `package:universal_web/js_interop.dart`, which stubs on the VM.
- **The page description is unreadable by default** — `DocsLayout` sets
  `font-size: 1.25rem` with `line-height: 1.25rem`, so any description that
  wraps collides with itself. Override it.

### How to drive the browser

Chrome DevTools Protocol over a WebSocket is enough; no Selenium or Playwright.

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --remote-debugging-port=9333 --remote-allow-origins='*' \
  --user-data-dir=/tmp/cdp about:blank
```

Then `Page.navigate`, `Input.dispatchKeyEvent`, `Runtime.evaluate`,
`Page.captureScreenshot`. Assert on: hydration, ⌘K opening the dialog, the
index actually being fetched (`performance.getEntriesByType('resource')`),
result count, `<mark>` highlighting, arrow-key selection, Enter navigating, Esc
closing, scroll-lock release, and the sidebar's open-group count.

Two traps: pass `--remote-allow-origins='*'` or the WebSocket handshake 403s,
and send `type: "char"` only for text — sending `keyDown` *and* `char` types
every character twice (`lliisstteenn`).

**And take screenshots.** Every assertion above passed while the dialog was 2px
tall.

---

## 8. Order of work

1. Build the current site and read the generated HTML. Find the silent bugs.
2. Write `navigation.dart`. Let the reachability check tell you what is orphaned.
3. Index generator + `--check` + tests. Get the anchor test green.
4. Sidebar, breadcrumbs, prev/next.
5. Search UI. **Screenshot it.**
6. Landing page and cards.
7. Full build → tests → browser run → screenshots at desktop, mobile, light, dark.
8. Wire CI, then deploy.

## 9. Local traps that cost time

- **`jaspr build` deletes and recreates `build/jaspr/`.** A `python3 -m http.server`
  started inside that directory keeps serving the deleted inode and returns
  stale content and spurious 404s. Restart the static server after every build.
- **`jaspr serve`/`build` bind 8080, 5567 and 8181.** An interrupted run leaves
  them held, and the next build fails with `Address already in use` — buried
  under a stack trace that looks like a code error. Kill them first.
- **Do not run a dev server as a timeout-bounded background task.** It gets
  SIGKILLed at the timeout, mid-session. Use `nohup … &` + `disown`.
