---
title: Photo Tables
description: Storing and serving binary file uploads with the built-in _photos table.
---

`_photos` is a built-in reserved table. You don't define a schema file for it — Zonai manages it automatically. It is designed for binary file uploads: images, documents, or any blob.

<Info>

Rows that store photo IDs can still be watched with `db.listen` / `/db/stream*` like any other table. See [Streaming](/operations/streaming).

</Info>

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

```dart no-analyze
avatarId = $.photo('avatar_id', (s) => s.avatarId),
profileImages = $.photos('profile_images', (s) => s.profileImages), // photo IDs
```

<Info>

If you want/need to clean up the image during a row update, you can delete the `_photos` row in an `afterDeleteSuccess` extension.

</Info>

## Storage

By default, photos are written to disk under the configured images directory (default: `.zonai/data/images/`), organized by the `table` field from the upload metadata:

```
.zonai/data/images/<table>/<id>.<ext>
```

For example, a JPEG uploaded for the `users` table might be stored at `.zonai/data/images/users/ph_abc123.jpeg`.

**Deleting a photo row also deletes the file.** When you call `DELETE /img/:id`, Zonai removes both the `_photos` database record and the stored file in the same operation.

### S3-compatible buckets (Cloudflare R2)

Set `AppConfig.photos.storage` to an `S3PhotoStorage` to keep photos in a bucket instead of on the server's disk. Keys keep the same layout, `<table>/<id>.<ext>`, inside the bucket:

```dart in:app-config
photos: PhotosConfig(
  storage: S3PhotoStorage(
    endpoint: 'https://<account-id>.r2.cloudflarestorage.com',
    bucket: 'my-app-photos',
    region: 'auto', // the default; R2 takes 'auto'
  ),
),
```

| Field | Meaning |
|-------|---------|
| `endpoint` | The S3 API URL, without the bucket. For R2 that's `https://<account-id>.r2.cloudflarestorage.com`. Requests are path-style (`<endpoint>/<bucket>/<key>`), so any S3-compatible service works, MinIO included. |
| `bucket` | The bucket name. Create it first; Zonai doesn't. |
| `region` | The SigV4 signing region. Defaults to `auto`, which is what R2 expects; use the bucket's region (such as `us-east-1`) for AWS S3. |
| `publicBaseUrl` | Optional. The bucket's public URL (an R2 custom domain or `r2.dev` address). Only used when `redirect` is on — see [Serving photos from the bucket](#serving-photos-from-the-bucket). |
| `redirect` | `false` (the default) streams every photo through the server. `true` answers `GET /img/:id` with a `302` to the bucket instead. |
| `presignedUrlSeconds` | How long a presigned redirect stays valid. Defaults to `300` (five minutes); at most `604800` (seven days), the SigV4 limit. |

Then give the server the bucket's credentials at runtime. For R2, create an API token with **Object Read & Write** on the bucket and use its access key ID and secret:

```bash
S3_ACCESS_KEY_ID=... \
S3_SECRET_ACCESS_KEY=... \
  ./zonai serve --release
```

The keys are read from the process environment only — see [Environment Variables](/configuration/environment-variables#overriding-a-baked-in-secret-at-runtime). The server refuses to start without them.

`GET /img/:id` reads the photo from the bucket and streams it to the caller with the same rule checks and caching headers as local storage; its `ETag` is the bucket's own content hash. The unreferenced-photo cleanup and the storage metrics list and delete objects in the bucket.

#### Serving photos from the bucket

With `redirect: true`, the server stops proxying photo bytes. `GET /img/:id` still checks your `canView` rules first, exactly as when streaming, and then answers `302 Found` with a `Location` the browser follows to the bucket:

```dart in:app-config
photos: PhotosConfig(
  storage: S3PhotoStorage(
    endpoint: 'https://<account-id>.r2.cloudflarestorage.com',
    bucket: 'my-app-photos',
    publicBaseUrl: 'https://images.example.com',
    redirect: true,
  ),
),
```

Which URL the redirect points at depends on whether a caller **with no JWT** could view the photo — the same check that picks `public` or `private` in [Caching and CDNs](/rules/photo-rules#caching-and-cdns):

| Photo | Redirect to | `Cache-Control` on the 302 |
|-------|-------------|----------------------------|
| Viewable anonymously, `publicBaseUrl` set | `<publicBaseUrl>/<key>?v=<etag>` | `public, no-cache`, with the `ETag`; a matching `If-None-Match` still gets a `304` |
| Anything else | A presigned SigV4 `GET` URL that expires after `presignedUrlSeconds` | `private, no-store`, no `ETag` |

- The public URL only works if the bucket (or its custom domain) serves objects publicly. For R2, connect a custom domain or enable the `r2.dev` address on the bucket. The `?v=` part changes whenever `PATCH /img/:id` replaces the image, so a CDN in front of that domain fetches the new bytes, not a stale copy.
- A restricted photo is never sent to the public URL. Its presigned link grants access on its own, so the redirect is `no-store`: no browser or shared cache keeps it, and every view goes back through your rules for a fresh link.
- Without `publicBaseUrl`, every photo gets a presigned redirect.
- A caller the rules refuse gets the same refusal as when streaming, never a redirect.

Browsers (an `<img src>`, for example) and other HTTP clients that follow redirects need no changes. With local storage `redirect` doesn't apply; photos are always streamed.

Switching backends doesn't move existing photos by itself: `_photos` rows pointing at photos still on disk will 404 until the files are in the bucket under the same keys. `zonai db migrate-photos` copies them.

#### Moving existing photos into the bucket

Run it from the project, on the machine that holds the images directory, with the new `S3PhotoStorage` config in place and the same two keys the server uses:

```sh
export S3_ACCESS_KEY_ID=... S3_SECRET_ACCESS_KEY=...
zonai db migrate-photos --dry-run   # list what would be copied
zonai db migrate-photos             # copy, keeping the local files
```

Every photo (`<table>/<id>.<ext>`) under the images directory is uploaded to the same key in the bucket, and the bucket is then asked for the object's size; a mismatch is reported as a failure. A photo the bucket already holds at the same size is skipped, so the command is safe to repeat. Run it again if it was interrupted or reported failures, and once more after the server has switched over, to pick up photos uploaded in between. The brand assets (`favicon.ico`, `logo.png`) stay on disk, since the server reads them from there.

Local files are left alone. Once the server is serving from the bucket, `--delete-local` deletes each local photo after checking that the bucket holds it at the same size. See [`zonai db migrate-photos`](/cli/db#db-migrate-photos).

**File size limit** — configured via `AppConfig.photos`:

```dart in:app-config
photos: PhotosConfig(
  maxBytes: 5 * 1024 * 1024,  // 5 MB default
  allowedMimeTypes: [ImageMimeType.jpeg, ImageMimeType.png],
),
```

These constraints are enforced before rules run, so `canCreate` in [photo rules](/rules/photo-rules) only sees valid files.

## Unreferenced Photo Cleanup

Zonai runs a built-in cron job (`_cleanup_unreferenced_photos`) daily at 5:00 AM that scans every table for `photo` and `photos` columns. Any `_photos` row whose ID does not appear in any of those columns is deleted along with its file on disk.

Photos uploaded within the last hour are exempt from cleanup, giving your app time to associate them with a record before the next scan runs.

- [Photo Rules](/rules/photo-rules) — control who can upload, view, and delete photos
