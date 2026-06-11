---
title: Photo Tables
description: Storing and serving binary file uploads with the built-in _photos table.
---

`_photos` is a built-in reserved table. You don't define a schema file for it — Zonai manages it automatically. It is designed for binary file uploads: images, documents, or any blob.

## Uploading a Photo

```
POST /img?meta={"table":"users"}
Content-Type: image/jpeg

<raw binary>
```

The image bytes are the raw request body. Pass metadata as a `meta` query parameter containing a JSON object with a `table` field that names the collection the photo belongs to.

Returns the created `_photos` row including its `id`:

```json
{
  "data": {
    "id": "abc123",
    "mimeType": "image/jpeg",
    "size": 204800,
    "createdAt": "2024-01-01T00:00:00.000Z"
  }
}
```

Access control is enforced by [Photo Rules](/rules/photo-rules).

## Serving a Photo

```
GET /img/:id
```

Streams the file bytes with the correct `Content-Type` header. Control access via photo rules.

## Replacing a Photo

```
PATCH /img/:id
Content-Type: image/png

<raw binary>
```

Replaces the stored bytes for an existing photo. The `id` must match an existing `_photos` row.

## Deleting a Photo

```
DELETE /img/:id
```

Removes the photo record and its stored bytes.

## Referencing Photos from Other Tables

Store the `_photos` row ID in a column on any table that owns the photo:

```dart
avatarId = $.photo('avatar_id', (s) => s.avatarId),
profileImages = $.photos('profile_images', (s) => s.profileImages), # array of photo IDs
```

<Info>
If you want/need to clean up the image during a row update, you can delete the `_photos` row in an `afterDeleteSuccess` extension.
</Info>

## Storage

Photos are written to disk under the configured images directory (default: `.zonai/data/images/`), organized by the `table` field from the upload metadata:

```
.zonai/data/images/<table>/<id>.<ext>
```

For example, a JPEG uploaded for the `users` table might be stored at `.zonai/data/images/users/ph_abc123.jpeg`.

**Deleting a photo row also deletes the file.** When you call `DELETE /img/:id`, Zonai removes both the `_photos` database record and the file from disk in the same operation.

**File size limit** — configured via `AppConfig.photos`:

```dart
photos: PhotosConfig(
  maxBytes: 5 * 1024 * 1024,  // 5 MB default
  allowedMimeTypes: [ImageMimeType.jpeg, ImageMimeType.png],
),
```

These constraints are enforced before the rules worker runs, so `canUpload` in photo rules only sees valid files.

## Unreferenced Photo Cleanup

Zonai runs a built-in cron job (`_cleanup_unreferenced_photos`) daily at 5:00 AM that scans every table for `photo` and `photos` columns. Any `_photos` row whose ID does not appear in any of those columns is deleted along with its file on disk.

Photos uploaded within the last hour are exempt from cleanup, giving your app time to associate them with a record before the next scan runs.

- [Photo Rules](/rules/photo-rules) — control who can upload, view, and delete photos
