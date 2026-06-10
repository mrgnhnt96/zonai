---
title: Photo Rules
description: Controlling who can upload, view, and delete photos.
---

The `_photos` table has its own rules class. Without a photo rules file, uploads and deletes are denied; viewing is public by default.

## Creating Photo Rules

Create a file in `rulesPath` (conventionally `photos_rules.dart`) extending `PhotoRules`:

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppPhotoRules main() => AppPhotoRules();

final class AppPhotoRules extends PhotoRules {
  @override
  Future<bool> canUpload(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canView(Jwt? jwt, Photo photo) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Photo photo) async {
    if (jwt?.admin.isAdmin ?? false) return true;
    return jwt?.userId == photo.ownerId;
  }
}
```

## Available Methods

| Method                  | Endpoint           | Default |
| ----------------------- | ------------------ | ------- |
| `canUpload(jwt)`        | `POST /img`        | `false` |
| `canView(jwt, photo)`   | `GET /img/:id`     | `true`  |
| `canDelete(jwt, photo)` | `DELETE /img/:id`  | `false` |

The `photo` parameter contains the metadata row for the file (MIME type, size, who uploaded it, etc.).

## File Constraints

File size and MIME type constraints are enforced **before** rules run — they are configured in `AppConfig.photos`. Your `canUpload` rule only sees valid uploads that have already passed the size and type checks.

```dart
photos: PhotosConfig(
  maxBytes: 5 * 1024 * 1024,
  allowedMimeTypes: [ImageMimeType.jpeg, ImageMimeType.png],
),
```

## Common Patterns

```dart
// Authenticated upload, public viewing
@override Future<bool> canUpload(Jwt? jwt) async => jwt != null;
@override Future<bool> canView(Jwt? jwt, Photo photo) async => true;

// Owner-only delete
@override Future<bool> canDelete(Jwt? jwt, Photo photo) async =>
    jwt?.userId == photo.ownerId;
```
