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

## Caching and CDNs

`GET /img/:id` (and `HEAD`) answers with two caching headers:

| Header          | Value                                                           |
| --------------- | --------------------------------------------------------------- |
| `ETag`          | A strong tag derived from the stored file's size and modification time |
| `Cache-Control` | `public, no-cache` or `private, no-cache`                        |

`no-cache` lets a browser or CDN keep a copy but makes it check with the server before reusing it. The check is cheap: the cache sends the tag it holds in `If-None-Match`, and while the photo is unchanged the server answers `304 Not Modified` with no body. The rules still run on every check, so a caller who has lost access gets their refusal, not the cached copy.

Photos are never marked `immutable` or given a `max-age`, because `PATCH /img/:id` replaces the image behind the same URL. The replacement gets a new `ETag`, so the next check downloads it rather than reusing the old image.

`public` or `private` comes from your view rules. On each view the server also asks your collection and row `canView` rules whether a caller **with no JWT** could see this photo:

- Yes: `public`, so a CDN or proxy may store it and serve it to anyone.
- No: `private`, so only the requesting browser may keep it. A shared cache must not store it, because it would hand the photo to every later caller without asking your rules.

A rule that throws when given a null JWT counts as no. With the built-in rules every photo is viewable without a JWT, so photos are `public` until you restrict `canView`.

With an S3 bucket and `redirect: true`, the server answers with a `302` to the bucket instead of the bytes, after the same rules. A redirect to the bucket's public URL keeps the headers above. A redirect to a presigned URL, used for every restricted photo, is `private, no-store` with no `ETag`, so no cache reuses a link that grants access by itself. See [Serving photos from the bucket](/schemas/photo-tables#serving-photos-from-the-bucket).

<Warning>

A CDN rule that caches `/img/*` regardless of the origin's `Cache-Control` (a "cache everything" rule, an edge TTL override, or ignoring `private`) bypasses these rules. The CDN stores the first response it sees, restricted photos included, and serves it to callers your `canView` rules would refuse. If any photo is restricted, leave the origin's `Cache-Control` in charge for `/img/*`.

</Warning>

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

Only `_photos` can be overridden this way. Registering rules for any other framework table (`_jwt`, `_log`, `_rate_limit`, `_auth_challenges`, …) fails when the rules load with `Table rules already registered for <table>`.

After adding or changing these files, recompile (`zonai compile`, or press `c` while `zonai serve` is running) and restart `serve`.

## File Constraints

File size and MIME type constraints are enforced **before** rules run — they are configured in `AppConfig.photos`. Your `canCreate` rule only sees uploads that have already passed the size and type checks.

```dart in:app-config
photos: PhotosConfig(
  maxBytes: 5 * 1024 * 1024,
  allowedMimeTypes: [ImageMimeType.jpeg, ImageMimeType.png],
),
```
