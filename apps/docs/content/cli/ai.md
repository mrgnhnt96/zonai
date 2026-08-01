---
title: zonai ai
description: Install AI coding assistant reference sheets for your Zonai project.
---

Install reference files that teach AI coding assistants how Zonai works — schemas, rules, operations (including **live streams** / `db.listen`), extensions, rate limits, crons, and CLI commands.

```sh
zonai ai <tool> [flags]
```

Run this from your project root. Files are skipped if they already exist; pass `--force` to overwrite.

## Tools

| Tool           | Command             | Files created                               |
| -------------- | ------------------- | ------------------------------------------- |
| All tools      | `zonai ai all`      | All files below                             |
| Claude Code    | `zonai ai claude`   | `CLAUDE.md`                                 |
| Cursor         | `zonai ai cursor`   | `.cursor/rules/zonai-*.mdc` (7 topic files) |
| GitHub Copilot | `zonai ai copilot`  | `.github/copilot-instructions.md`           |
| Windsurf       | `zonai ai windsurf` | `.windsurfrules`                            |
| Cline          | `zonai ai cline`    | `.clinerules`                               |

For Cursor, each `.mdc` file covers a specific topic (overview, schemas, rules, operations, extensions, rate limits, crons) and is attached automatically when you edit matching files.

## Examples

```sh
# Install reference files for Cursor
zonai ai cursor

# Install for every supported tool
zonai ai all

# Overwrite existing files
zonai ai cursor --force
```

## What's in the reference sheets

The generated files are a condensed Zonai framework reference: project layout, `zonai.yaml` paths, table and auth schema patterns, authorization rules, lifecycle extensions, rate-limit policies, cron jobs, email templates, common CLI commands, and **live query streams** (`/db/stream*` / `client.db.listen` — do not tell agents to poll).

They are meant to be committed to your repo so every developer (and their AI assistant) gets consistent context about how your Zonai project is structured.

<Info>
Reference files are generated from the Zonai CLI version you run. Re-run `zonai ai <tool> --force` after upgrading Zonai if you want the sheets to reflect new framework features (including streaming). Also see the public [llms.txt](/llms.txt) and [Streaming](/operations/streaming) docs.
</Info>
