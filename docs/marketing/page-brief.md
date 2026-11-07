# Page brief

- Type and state: developer tool home page, live. One page at zonai.dev; the docs are a separate site at docs.zonai.dev.
- Audience: Dart and Flutter developers who want a backend without leaving Dart. They know what REST, auth and SQLite are, and may be comparing Zonai with Firebase, Supabase or Serverpod.
- The page's one job: show a Dart developer that a table definition gets them a working, self-hosted backend, and send them to the quick start.
- Primary CTA: "Start building" in the hero, "Get Started" in the nav and final section. All three go to the docs quick start (`https://docs.zonai.dev/getting-started/quick-start`).
- Secondary action: "Star on GitHub".
- Search phrases: dart backend framework; self-hosted dart backend; flutter backend self hosted; dart rest api framework; firebase alternative for flutter.
- Objections: Is it real and can I read it? (open source, real dashboard capture, code that compiles.) Do I have to host it? (What Zonai is not.) Can it do live data? (Live queries.) What do I get beyond CRUD? (Features.) How long until something runs? (Quick Start.)
- Analytics and cookies: none. No third-party requests: fonts are served from the site.

## Sections

| Section | Why it stays |
| --- | --- |
| Hero | Says what it is, with the code you write and the routes you get. |
| Live Queries | The feature most people arrive looking for. |
| Dashboard | Answers "what do I get beyond an API?" with a real capture. |
| Features | The rest of the box. Live queries and the dashboard have their own sections, so they have no card. |
| What Zonai is not | Lets someone rule it out early. |
| Quick Start, with downloads | The primary CTA. Downloads sit here because they are step one. |
| Final CTA | One last route to the docs and the source. |

Pipeline and Tour were cut: both repeated what Features and Quick Start say.

## Claims

| Claim on the page | Evidence |
| --- | --- |
| Free, open source, MIT licensed | `LICENSE` |
| Self-hosted; no account, no per-seat bill | `apps/docs/content/deployment/running-the-server.md`; no hosted service exists in the repo |
| 12 routes for every table, with bulk writes on `/db/many` | `apps/docs/content/operations/default-operations.md` |
| No handler code, no generation step for the API | `apps/docs/content/index.md`; routes come from the schema at runtime |
| Hero and Live Queries code samples | Compiled 2026-11-06: the hero sample inside a real v0.13.1 project, the live sample against `libs/zonai_client` |
| Three streaming routes; a new payload when the result changes; no WebSocket server or broker | `apps/docs/content/operations/streaming.md` |
| The streaming panel is a simulation | Labelled "simulated demo" on the page; it runs on a timer in `apps/website/lib/src/interactive/stream_demo.dart` |
| Dashboard served at `/_`, compiled in with the API | Seen on a real v0.13.1 server, 2026-11-06 |
| On a new project, add `lib/src/rules/admin_row_rules.dart` before you sign in | Seen on a real v0.13.1 project, 2026-11-06; backlog B783 |
| Dashboard capture | Real v0.13.1 dashboard on a local test project, with seven example rows typed in for the capture. The page caption says it is example data. Captured 2026-11-06 with a headless browser. |
| Dashboard capabilities and `GET /dashboard/metrics` | `apps/docs/content/dashboard/overview.md`, `apps/docs/content/api/openapi-spec.md` |
| Table rules run before SQL, row rules check each fetched row, one failure returns a 403 with no data | `apps/docs/content/core-concepts/request-pipeline.md` |
| Without both rules files, requests are refused; anything not overridden is admin-only | `apps/docs/content/rules/overview.md`, `apps/docs/content/rules/table-rules.md`, `apps/docs/content/rules/row-rules.md` |
| Auth methods, sessions, refresh, logout | `apps/docs/content/authentication/overview.md` |
| Email, push, cron, rate limiting | `apps/docs/content/extensions/side-effects-push.md`, `apps/docs/content/authentication/`, `apps/docs/content/deployment/running-the-server.md` |
| `./zonai build` writes everything into `build/`; cross-compile for Linux; no Dart SDK on the server | `apps/docs/content/deployment/building-for-production.md`, `apps/docs/content/deployment/cross-compilation.md` |
| macOS and Linux in one file, Windows as a zip | Release assets, `.github/workflows`; `apps/docs/content/getting-started/installation.md` |
| Needs the Dart SDK 3.13.x | `apps/docs/content/getting-started/installation.md` |
| Quick Start steps | Run by hand on v0.13.1 on 2026-11-06; matches `apps/docs/content/getting-started/quick-start.md` |
| `./zonai version check`, `version update` | `apps/docs/content/cli` |
| The CLI asks GitHub for the latest release; `--no-version-check` skips it | `apps/zonai/lib/src/domain/versions.dart` |
| `./zonai ai` writes reference sheets for Claude Code, Cursor, Copilot, Windsurf and Cline | Checked against the `ai` command in `apps/zonai` on 2026-11-06 |

Download sizes are gone from the page: they went stale with each release.

## Waiting on a person

- Morgan: decide whether zonai.dev should have its own `llms.txt`. It returns 404 today, and the page links the docs one, which works.
- Morgan: after launch, verify the site in Google Search Console and Bing Webmaster Tools, and run the Rich Results Test on the deployed page.
- Fix needed outside the site: a freshly scaffolded project is missing the admin row rules, so admin sign-in fails until that file is added (backlog B783). The Dashboard section says so for now, and the docs Quick Start needs the same warning. Remove the line from the page once B783 ships.
