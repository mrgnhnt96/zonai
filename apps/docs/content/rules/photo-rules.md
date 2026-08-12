---
title: Photo Rules
description: Controlling who can upload, view, and delete photos.
---

The `_photos` table backs the photo HTTP API. It is a framework-managed table, but unlike the other internal tables its built-in rules are marked overridable — you can replace them with your own.

There is no dedicated `PhotoRules` base class. You write the same `TableRules` and `RowRules` you would for any collection, typed against the framework's `PhotosTable` and `PhotoEntry`, and pass the `photos` schema getter to the constructor.

## Creating Photo Rules

Add **both** files under `rulesPath` — a collection-rules file and a row-rules file, exactly as you would for one of your own tables. Registering only one leaves the other at its built-in default.

```dart
import 'package:zonai_schema/zonai_schema.dart';

PhotoTableRules main() => PhotoTableRules();

final class PhotoTableRules extends TableRules<PhotosTable, PhotoEntry> {
  PhotoTableRules() : super(photos);

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canView(Jwt? jwt) async => true;
}
```

```dart
import 'package:zonai_schema/zonai_schema.dart';

PhotoRowRules main() => PhotoRowRules();

final class PhotoRowRules extends RowRules<PhotosTable, PhotoEntry> {
  PhotoRowRules() : super(photos);

  @override
  Future<bool> canView(Jwt? jwt, PhotoEntry row) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, PhotoEntry row) async {
    if (jwt?.admin.isAdmin ?? false) return true;
    return jwt?.userId == row.ownerId;
  }
}
```

<Info>

Compare `jwt.userId` against `row.ownerId` directly — both are `Id`s. Comparing `jwt.userId` to `row.ownerId.value` compares an `Id` to a `String`, which is always false, and would silently deny every owner.

</Info>

## Endpoints and the rules they run

Each request runs the collection rule first, then the row rule when a row is involved.

| Photo API operation      | Table check | Row check   |
| ------------------------ | ----------- | ----------- |
| `POST /img`              | `canCreate` | `canCreate` |
| `GET /img/:id`           | `canView`   | `canView`   |
| `PATCH /img/:id`         | `canUpdate` | `canUpdate` |
| `DELETE /img/:id`        | `canDelete` | `canDelete` |

The `_photos` table is reached through this API, not through the generic `/db/*` routes.

## The PhotoEntry row

Row rules receive a `PhotoEntry`, exported from `package:zonai_schema/zonai_schema.dart`:

| Field            | Purpose                                                          |
| ---------------- | ---------------------------------------------------------------- |
| `row.id`         | Photo ID (`PhotoId`)                                             |
| `row.ownerId`    | The authenticated user at upload time, as an `Id`                |
| `row.ownerTable` | The auth collection that user came from                          |
| `row.table`      | The app collection the photo is attached to                      |
| `row.path`       | Relative path under the configured images directory              |
| `row.extension`  | Normalized file extension (`jpg`, `png`, …)                      |
| `row.createdAt`  | Upload time                                                      |

## Built-in defaults

Without override files, the built-in rules apply:

**Collection rules** — create, view, update and delete are all allowed, for every caller including unauthenticated ones.

**Row rules**:

| Method      | Default                                      |
| ----------- | -------------------------------------------- |
| `canView`   | Allowed for everyone                         |
| `canCreate` | Requires a JWT (`jwt != null`)               |
| `canUpdate` | Owner (`jwt.userId == row.ownerId`) or admin |
| `canDelete` | Owner or admin                               |

Note that your own `TableRules`/`RowRules` do **not** inherit these permissive defaults — the public base classes deny by default for non-admins, so once you add an override file you are responsible for every method it exposes.

Only `_photos` can be overridden this way. Registering rules for any other internal table (`_jwt`, `_log`, `_rate_limit`, `_auth_challenges`, `_raindrop_migrations`) raises a duplicate-registration error when the rules worker loads.

## File Constraints

File size and MIME type constraints are enforced **before** rules run — they are configured in `AppConfig.photos`. Your `canCreate` rule only sees uploads that have already passed the size and type checks.

```dart
photos: PhotosConfig(
  maxBytes: 5 * 1024 * 1024,
  allowedMimeTypes: [ImageMimeType.jpeg, ImageMimeType.png],
),
```
