---
title: Browsing & Editing Data
description: Read, filter, create and edit rows from the dashboard, with typed editors for every column kind.
---

`/_/tables` lists every table in the database — the ones you defined plus the
built-in ones such as `_photos`. Picking one opens it at
`/_/tables/<table>`, where the rows are shown in a grid you can sort, filter
and edit in place.

This is the fastest way to check what your schema actually produced, seed a bit
of data, or fix one bad row — without writing SQL or a `curl` command.

## Finding rows

- **Sort** by clicking a column.
- **Filter** per column. Date and time columns get a dedicated picker rather
  than making you type a timestamp format.
- **Search** from the side panel, for looking across a table rather than down
  one column.
- **Query preview** shows the query your filters and sort add up to, which is
  handy when you are working out the equivalent
  [`where` clause](/operations/default-operations) for your app code.

Selecting a row opens a detail panel with the full record — better than a wide
grid when a table has many columns.

## Editing

Cells are edited in place, and the editor matches the column's type rather
than making everything a text box:

| Column kind | Editor |
| --- | --- |
| Text | Text field |
| Number / big integer | Numeric field |
| Boolean | Toggle |
| Date and time | Date-time picker |
| Enum | Single- or multi-select |
| JSON | Structured JSON field |
| Password | Masked field |
| Photo | [Photo](/schemas/photo-tables) upload and preview |
| Foreign key | Row picker (below) |

New rows are created from the same screen.

### Foreign keys

A foreign-key column opens a **picker** over the referenced table instead of
asking you to paste an ID — you search for the row you mean and select it. The
value is validated against the target table, so a typo cannot leave a dangling
reference behind.

## What this bypasses, and what it does not

The dashboard talks to the same HTTP API your app does, as an admin. Two
consequences worth knowing:

- **Extensions still fire.** Creating or updating a row here runs the same
  [create](/extensions/create-hooks) and [update](/extensions/update-hooks)
  hooks as a request from your app, including any
  [side effects](/extensions/side-effects-mutate) such as sending email. A
  dashboard edit is not a quiet database write.
- **Live queries still update.** Anything watching those rows over
  [`/db/stream*`](/operations/streaming) receives the change, so you can edit a
  row in the dashboard and watch your app's UI react.

<Warning>

Admin sessions carry elevated claims, so your [row rules](/rules/row-rules)
will generally not restrict what the dashboard can see or change. Treat it as
direct access to production data.

</Warning>

## Related

- [Defining Tables](/schemas/defining-tables) — where the columns and types come from
- [Default Operations](/operations/default-operations) — the API the dashboard calls
- [Photo Tables](/schemas/photo-tables) — how photo columns are stored
- [Admin Accounts](/authentication/admin-accounts) — the elevated claims involved
