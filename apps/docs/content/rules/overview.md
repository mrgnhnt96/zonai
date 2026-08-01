---
title: Rules Overview
description: How Zonai's two-layer authorization model works.
---

Rules are the authorization layer in Zonai. Every request passes through rules before SQL runs. A denial returns `403 Forbidden` immediately — no SQL runs, no extension fires.

On the default path, rules run **in-process** inside the project-linked server binary (or JIT `project_main`). They are also compiled into `db_rules.exe` for `zonai ping`, compatibility, and `ZONAI_FORCE_WORKERS=1`. Restart `serve` (or rebuild) after editing rules so the linked entry reloads.

## Two Layers

**Table rules** evaluate whether the requesting JWT may perform an operation on a table at all. They do not see individual rows — only the JWT and the operation type.

- Applied to: `create`, `list`, `count`, `view`, `update`, `delete`, and auth operations
- File: `<table>_table_rules.dart`

**Row rules** run after the database returns results. They receive the JWT and the actual row data — enabling decisions like "only the owner may edit this."

If `canView` returns `false` for any row in the result set, the entire request returns `403 Forbidden`. For mutations, `canUpdate`/`canDelete` deny with `403` if false, aborting the mutation.

- Applied to: `view`, `list`, `update`, `delete`, `create` (with the data being inserted as the "row")
- File: `<table>_row_rules.dart`

Both layers must pass for a request to proceed. If the table rule denies, row rules never run.

## Return Value Semantics

Rule methods return `Future<bool>`:

- `true` → allowed, pipeline continues
- `false` → `403 Forbidden`, request stops immediately

This applies to all rule methods including `canView`. If a row fails `canView`, the entire request returns `403` — not a partial or filtered response.

<Info>
If no rules file exists for a table, **all operations on that table are denied by default**. This is intentional — tables start private and you explicitly open them up.
</Info>

## The JWT Parameter

Every rule method receives a `Jwt?` — nullable because the request may be unauthenticated:

```dart
// Public endpoint — allow everyone
@override
Future<bool> canList(Jwt? jwt) async => true;

// Authenticated endpoint — require sign-in
@override
Future<bool> canCreate(Jwt? jwt) async => jwt != null;

// Admin-only
@override
Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
```

See [JWT Claims](/rules/jwt-claims) for all available fields.

## Related

- [Table Rules](/rules/table-rules) — operation-level access control
- [Row Rules](/rules/row-rules) — per-row access control
- [Auth Rules](/rules/auth-rules) — sign-up/sign-in/password-reset control
- [JWT Claims](/rules/jwt-claims) — what's in the token
