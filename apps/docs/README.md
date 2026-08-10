# Zonai docs

The documentation site at <https://docs.zonai.dev/>, built with
[Jaspr Content](https://docs.jaspr.site/content) and published to GitHub Pages
by `.github/workflows/deploy-docs.yml`.

## Running locally

```sh
sip run docs start      # regenerates the search index, then `jaspr serve`
```

Or by hand, from this directory:

```sh
dart run tool/build_search_index.dart
dart run jaspr_cli:jaspr serve      # http://localhost:8080
```

`jaspr build` writes to `build/jaspr/`.

## How it fits together

**`lib/src/navigation.dart` is the single source of truth for the sidebar.** It
drives the sidebar groups, the breadcrumb, the previous/next links at the foot
of each page, the section cards on the landing page, and the section label on
search results. Adding a page under `content/` without adding it here is a
build failure, not a silently unreachable page.

**Search is client-side.** There is no backend, so
`tool/build_search_index.dart` walks `content/`, splits each page on its
headings, and writes `web/search-index.json`. The `DocsSearch` component
(`lib/components/search.dart`) fetches that file the first time the dialog is
opened and ranks it in the browser. The index is committed so a clean checkout
can `jaspr serve` without a generation step — `dart test` fails if it has gone
stale relative to `content/`.

Ranking itself lives in `lib/src/search_index.dart`, separate from the UI, so
`test/search_index_test.dart` can exercise it against the real index.

## Writing content

Pages are markdown under `content/`, with `title` and `description` front
matter. Available components:

| Component | Notes |
| --- | --- |
| `<Info>` `<Warning>` `<Error>` `<Success>` | Callouts |
| `<CardGrid columns="3">` + `<Card title href icon badge>` | Linked tiles |
| `<SectionCards />` | One card per sidebar group, generated from `navigation.dart` |

> **Leave a blank line inside every component block.** `package:markdown`
> treats an HTML block as literal text until it hits a blank line, so
> `<Info>\n**bold**\n</Info>` renders the asterisks. Write it as:
>
> ```md
> <Info>
>
> **bold** and [links](/getting-started/quick-start) work here.
>
> </Info>
> ```

## Tests

```sh
sip run docs test       # builds, then runs the suite
```

- `test/navigation_test.dart` — every sidebar link resolves to a page, every
  page is reachable, no duplicates, prev/next covers the whole reading order.
- `test/search_index_test.dart` — the committed index is current, known queries
  rank the right page first, and every result anchor exists as an `id` in the
  built HTML. The anchor test skips when `build/jaspr/` is absent.
