---
title: zonai ai
description: Install AI coding assistant reference sheets for your Zonai project.
---

Install reference files that teach AI coding assistants how Zonai works — schemas, rules, operations (including **live streams** / `db.listen`), extensions, rate limits, crons, and CLI commands.

```sh
zonai ai <tool> [flags]
```

Run this from your project root. Files are skipped if they already exist; pass `--force` to overwrite. A skipped file reports the Zonai version that wrote it, so you can tell an up-to-date sheet from a stale one.

## Tools

| Tool           | Command             | Files created                               |
| -------------- | ------------------- | ------------------------------------------- |
| All tools      | `zonai ai all`      | All files below                             |
| Claude Code    | `zonai ai claude`   | `CLAUDE.md`                                 |
| Cursor         | `zonai ai cursor`   | `.cursor/rules/zonai-*.mdc` (9 topic files) |
| GitHub Copilot | `zonai ai copilot`  | `.github/copilot-instructions.md`           |
| Windsurf       | `zonai ai windsurf` | `.windsurfrules`                            |
| Cline          | `zonai ai cline`    | `.clinerules`                               |
| _(refresh)_    | `zonai ai update`   | Rewrites only the files you already have    |

For Cursor, each `.mdc` file covers a specific topic (overview, schemas, operations, rules, views, extensions, rate limits, crons, release) and is attached automatically when you edit matching files.

## Examples

```sh
# Install reference files for Cursor
zonai ai cursor

# Install for every supported tool
zonai ai all

# Overwrite existing files
zonai ai cursor --force

# Rewrite the files this project already has, in place
zonai ai update
```

## Keeping them current

Every file Zonai writes ends with a version stamp:

```html
<!-- zonai:ai v0.8.3 -->
```

It renders as nothing, and it is what answers "which Zonai wrote this?".

`zonai ai update` rewrites the reference files your project **already has**, and nothing else — refreshing a stale `CLAUDE.md` will not drop `.windsurfrules`, `.clinerules` and a `.cursor/rules/` directory into a project that never asked for them. Use `zonai ai all --force` when you do want every tool installed.

After `zonai version update`, Zonai scans your project for reference files whose stamp names another release (or carries no stamp at all — every sheet written before stamping existed is in that state), lists them, and offers to refresh them. Answering yes runs the newly installed CLI, so you get the new release's prose rather than the outgoing one's. On Windows the executable is swapped after the CLI exits, so it prints the command instead of offering to run it.

## What's in the reference sheets

The generated files are a condensed Zonai framework reference: project layout, `zonai.yaml` paths, table and auth schema patterns, authorization rules, lifecycle extensions, rate-limit policies, cron jobs, email templates, common CLI commands, and **live query streams** (`/db/stream*` / `client.db.listen` — do not tell agents to poll).

They are meant to be committed to your repo so every developer (and their AI assistant) gets consistent context about how your Zonai project is structured.

<Info>

Reference files are generated from the Zonai CLI version you run, and stamped with it. `zonai version update` offers to refresh them; `zonai ai update` does it on demand. Also see the public [llms.txt](/llms.txt) and [Streaming](/operations/streaming) docs.

</Info>
