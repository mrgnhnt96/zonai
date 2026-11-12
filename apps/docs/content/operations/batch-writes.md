---
title: Batch Writes
description: Write across several tables in one request so that every write lands or none do.
---

`POST /db/batch` takes a list of writes, across any tables, and applies all of them or none of them. Use it when one change spans tables and a half-applied version would be wrong: moving ownership of an org, say, where the org's owner, its member roles and its pending invites have to change together.

Sending the same writes one request at a time and undoing them by hand on failure is not the same thing. A crash, a deploy or a dropped connection between two requests still leaves the change half done. A batch runs every step's SQL inside one SQLite transaction, so there is no in-between state for anything to stop in.

## From the Dart client

```dart in:client
final results = await client.db.batch(
  body: BatchBody(
    operations: [
      BatchOperation.update(
        UpdateOneBody(
          table: 'orgs',
          where: Eq('id', 'og_1'),
          updates: [ObjectUpdate({'owner_id': 'us_2'})],
          expect: Eq('owner_id', 'us_1'), // still owned by who we think
        ),
      ),
      BatchOperation.create(
        CreateBody(
          table: 'members',
          object: {'org_id': 'og_1', 'user_id': 'us_2', 'role': 'owner'},
        ),
      ),
      BatchOperation.deleteMany(
        DeleteBody(table: 'invites', where: Eq('org_id', 'og_1')),
      ),
    ],
  ),
);

for (final result in results) {
  print('${result.op} ${result.table}: ${result.count} row(s)');
}
```

`batch` returns one `BatchResult` per step, in the order the steps were sent: its `op`, `table`, `count` (rows written), and `rows`. For a create or an update, `rows` holds the same rows that route returns on its own. A delete returns no rows, as on its own route.

## The steps

Each step has the same fields as its single-write route, plus an `op` naming it.

| `op` | Same as | Matching nothing |
| --- | --- | --- |
| `create` | `POST /db` | — |
| `createMany` | `POST /db/many` | — |
| `update` | `PATCH /db` | Fails the batch with `404` |
| `updateMany` | `PATCH /db/many` | Not an error; `count` is `0` |
| `delete` | `DELETE /db` | Fails the batch with `404` |
| `deleteMany` | `DELETE /db/many` | Not an error; `count` is `0` |

On the wire:

```json
// Request body: POST /db/batch
{
  "operations": [
    {
      "op": "update",
      "table": "orgs",
      "where": { "type": "eq", "column": "id", "value": "og_1" },
      "updates": [{ "type": "object", "object": { "owner_id": "us_2" } }],
      "expect": { "type": "eq", "column": "owner_id", "value": "us_1" }
    },
    {
      "op": "create",
      "table": "members",
      "object": { "org_id": "og_1", "user_id": "us_2", "role": "owner" }
    },
    {
      "op": "deleteMany",
      "table": "invites",
      "where": { "type": "eq", "column": "org_id", "value": "og_1" }
    }
  ]
}

// Response
{
  "data": [
    { "op": "update", "table": "orgs", "count": 1, "rows": [{ "id": "og_1", "owner_id": "us_2", ... }] },
    { "op": "create", "table": "members", "count": 1, "rows": [{ "id": "mb_9", ... }] },
    { "op": "deleteMany", "table": "invites", "count": 2, "rows": [] }
  ]
}
```

An empty `operations` list is allowed and returns `{ "data": [] }`. More than 100 steps is a `400`; split the work into several batches.

## How a batch runs

1. **Every step is checked first.** Table and row [rules](/rules/overview), `before*` hooks, password hashing and an update's `expect` all run for every step, in order, before anything is written.
2. **Then every step's SQL runs in one transaction.** If any statement fails (a unique or foreign-key violation, say), the transaction rolls back and the steps before it are undone.
3. **Then the `after*Success` hooks run**, once the whole batch has committed, in step order. As for a single write, a failing after hook is logged and the writes stand.

### Steps don't see each other's writes

Every step is checked against the database as it stood **before** the batch. A later step does not see what an earlier step wrote:

- An `updateMany` or `deleteMany` does not match a row an earlier `create` in the same batch added.
- A rule or hook that reads the database sees the rows as they were before the batch.

Order the steps, or shape the `where`s, with that in mind. In the example above, the `create` adds the new owner's membership and nothing later in the batch needs to find it.

One case is caught for you: when an earlier step changes a row so that it no longer meets a later update's `expect`, the batch is refused with `412`. Its `current` is empty, because the row that failed was only ever written inside the rolled-back transaction.

## When a step fails

The batch fails as a whole, with the error the failing step would get from its own route: `403` for a rule or a hook's refusal, `404` for an `update` or `delete` that matches nothing, `409` for a unique violation, `412` for a failed `expect`, `422` for a foreign-key violation. Nothing is written. In the Dart client, a failed `expect` throws `PreconditionFailedException` and everything else throws `ServerException`.

A batch cannot delete from `_photos`: deleting a photo row also deletes its file, which a rollback cannot bring back. Such a batch is refused with `400`; delete photos with their own request.

## Rate limits

Each step counts against its own table's limit for its kind of write, exactly as the same write sent on its own would. A batch is not a way around a table's limits. The first step over its limit refuses the whole batch with `429` and nothing is written, though the steps before it in the batch have still been counted. See [Rate Limiting](/rate-limiting/overview).

## Older servers

A server older than this feature answers `POST /db/batch` with `404`. Know your server version before you rely on it.
