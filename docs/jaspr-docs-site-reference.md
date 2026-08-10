# Reference: files, APIs and gotchas for a Jaspr Content docs site

Companion to [`jaspr-docs-site-playbook.md`](./jaspr-docs-site-playbook.md),
which explains *why*. This one is the lookup table: what to create, which
Jaspr/`jaspr_content` APIs actually exist, and the specific things that fail.

Versions this was verified against: `jaspr 0.23.3`, `jaspr_content 0.5.2`,
`jaspr_cli 0.23.1`, `universal_web 1.1.1+1`, `markdown 7.3.1`, Dart 3.12.2.

---

## File layout

```
apps/docs/
  content/                       markdown pages (URLs derive from paths)
    _data/site.yaml              title, description, url, base, social
  lib/
    main.server.dart             ContentApp + layout + component registry
    main.client.dart             ClientApp (untouched)
    src/
      navigation.dart            THE information architecture
      search_index.dart          index model + ranking (no DOM — testable)
    components/
      docs_sidebar.dart          collapsible <details> sidebar
      search.dart                @client ⌘K dialog
      cards.dart                 CardGrid / Card / SectionCards
  tool/
    build_search_index.dart      content/ -> web/search-index.json
  test/
    navigation_test.dart
    search_index_test.dart
  web/
    search-index.json            generated, committed
    CNAME                        custom domain (see deployment doc)
```

`pubspec.yaml` needs `test:` added under `dev_dependencies`. Nothing else.
`universal_web` arrives transitively via `jaspr`.

---

## Jaspr API notes

Things that cost a compile cycle each to discover.

### Element helpers

| Need | Use |
| --- | --- |
| Text node | `Component.text('…')` — bare `text()` is deprecated |
| An element with no helper (e.g. `<mark>`) | `Component.element(tag: 'mark', children: […])` |
| Nothing | `const Component.empty()` |
| Raw HTML (inline SVG) | `RawText('<svg …>')` |
| Arbitrary DOM event | `events: {'keydown': (web.Event e) { … }}` |

`details(children, {open, classes, …})` and `summary(…)` exist. `mark` and
`kbd` do not.

Children are the **first positional** argument, but Dart allows named arguments
before positionals, so `div(classes: 'x', [child])` is valid and is the
house style.

### Style API

| Wrong | Right |
| --- | --- |
| `TextTransform.uppercase` | `TextTransform.upperCase` |
| `TextDecoration.underline` | `TextDecoration(line: TextDecorationLine.underline)` |
| `Border.all(BorderSide(…))` | `Border.all(width: 1.px, color: …)` |
| `marginTop: 4.px` | `margin: Margin.only(top: 4.px)` |

Anything without a typed property goes through
`raw: {'grid-template-columns': '…'}`.

Components emit their own CSS with
`Document.head(children: [Style(styles: _styles)])`, following
`jaspr_content`'s own components. Guard it with `if (!kIsWeb)` in `@client`
components so it is server-rendered once.

### Client components

- `@client` on a `StatefulComponent`; `jaspr_builder` registers it in
  `main.client.options.dart` automatically.
- Props must be JSON-serializable. Prop-less is simplest.
- `context.binding.addPostFrameCallback(…)` for anything needing the DOM.
  `Future.microtask` runs **before** the DOM is flushed.
- `GlobalNodeKey<T>.currentNode` returns null for `universal_web` element types
  under dart2js — the pattern match `RenderObject(:final T node)` does not
  survive extension-type erasure. **Look elements up by `id`.**
- Import `package:universal_web/js_interop.dart`, never `dart:js_interop`: a
  `@client` component in the header is compiled for the server, where
  `dart:js_interop` is an unavailable library and the build fails with
  `The unavailable library 'dart:js_interop' is imported through these packages`.
- `web.window.onKeyDown.listen(…)` gives a Dart `Stream<KeyboardEvent>`.
- Fetch: `await web.window.fetch(url.toJS).toDart`, then
  `(await response.text().toDart).toDart`.

### Custom markdown components

```dart
final class CardGrid extends CustomComponentBase {
  const CardGrid();
  @override
  Pattern get pattern => 'CardGrid';           // note `=>`, it is a getter
  @override
  Component apply(String name, Map<String, String> attributes, Component? child) => …;
}
```

Register in `ContentApp(components: [...])`. Then in markdown:

```md
<CardGrid columns="3">

<Card title="Quick Start" href="/getting-started/quick-start" icon="rocket">

Body text. **Markdown works here** because of the blank lines.

</Card>

</CardGrid>
```

**The blank lines are mandatory.** See the playbook §4.

### Overriding `DocsLayout`

`DocsLayout` has no hook between the sidebar and the page title, so breadcrumbs
mean overriding `buildBody` and reproducing its DOM. Keep the class names
identical — `super.buildHead(page)` still emits the upstream CSS, which targets
them. Note in a comment that this shadows upstream markup and must follow it.

`footer` is a single component for all pages, but it can be a `Builder` that
reads `context.page`, or you can render per-page content directly in your
`buildBody` override.

Careful: inside a `DocsLayout` subclass, the bare identifier `header` resolves
to Jaspr's `<header>` element class, not the inherited field. Write
`this.header`. The symptom is a baffling
`The element type 'Type' can't be assigned to the list type 'Component'`.

---

## Search index format

```json
{
  "v": 1,
  "docs": [
    {
      "u": "/operations/streaming",
      "t": "Streaming (Live Queries)",
      "d": "one-line description",
      "g": "Querying Data",
      "s": [
        {"b": "intro text, no heading, no anchor"},
        {"h": "Endpoints", "a": "endpoints", "b": "section text"}
      ]
    }
  ]
}
```

Short keys because the file ships to every searching reader. `t` is the page's
own front-matter title (what the `<h1>` says), not the sidebar label — sidebar
labels get shortened to fit the column and would read wrong in results.

### Markdown → prose

In order:

1. Strip HTML comments, then component/HTML tags.
2. `![alt](src)` → `alt`, `[text](url)` → `text`.
3. Strip blockquote markers, list bullets, table delimiter rows, `|`.
4. Strip `` ` ``, `*`, `#`. **Keep `_`** — see playbook §3.
5. Collapse whitespace.

Split on `^(#{2,3})\s+`, tracking fence state so `#` inside ``` blocks is not
treated as a heading. Keep code contents; drop only the fence lines. Cap each
section (~1200 chars) so the file stays one fast download.

### Anchor slugs

```dart
String anchorFor(String rawHeading) => rawHeading
    .toLowerCase().trim()
    .replaceAll(RegExp('[^a-z0-9 _-]'), '')
    .replaceAll(RegExp(r'\s'), '-');
```

`package:markdown`'s `HeaderWithIdSyntax` runs during *block* parsing, when the
heading's only child is still `UnparsedContent` — the raw text including
backticks and link syntax. Hence `## Prefer \`zonai_client\`` →
`prefer-zonai_client`. `jaspr_content` uses `node.generatedId` with no
uniquifying pass, so duplicate headings collide; a test against the built HTML
will tell you if that bites.

### Ranking weights

Per token, all must match:

| Where | Points |
| --- | --- |
| page title, as a prefix | 46 |
| page title, anywhere | 30 |
| section heading | 18 |
| description | 10 |
| body | 6 |
| group name | 4 |

Whole-phrase bonuses: title prefix +70, title contains +40, heading +20,
body +12. Intro section (no heading) +14. Cap 3 hits/page, 24 total.

---

## Deployment-shaped constraints

Covered fully in
[`jaspr-docs-site-deployment.md`](./jaspr-docs-site-deployment.md); the two that
affect *code*:

- **Resolve client-built URLs against `<base href>`.** Links rendered in the
  browser miss any absolute-URL rewrite a deploy does. `Uri.parse(web.document.baseURI).resolve(path)`
  is correct at a domain root and under a `/repo/` subpath.
- **Store index URLs root-absolute** (`/operations/streaming`) so they match
  `page.url` for navigation lookups, and resolve at click time.

---

## Commands

```sh
dart run tool/build_search_index.dart            # regenerate the index
dart run tool/build_search_index.dart --check    # fail if stale (CI/tests)
dart run jaspr_cli:jaspr serve                   # http://localhost:8080
dart run jaspr_cli:jaspr build                   # -> build/jaspr/
dart analyze --fatal-infos
dart test                                        # run AFTER a build for anchors
```

`jaspr serve` hot-reloads `content/`. It does **not** pick up a stale search
index (regenerate manually) or changes to `navigation.dart` (restart).
