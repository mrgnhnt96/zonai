---
title: Photos
description: Uploading, downloading, and deleting photos with the Dart client.
---

The `photos` property on `ZonaiClient` wraps the server's photo endpoints.
Images are transferred as byte streams — no intermediate buffering required.

## Upload a Photo

Photo bodies are `Stream<List<int>>`, so `dart:io`'s `File.openRead()` is the
usual source:

```dart in:client
final result = await client.photos.create(
  image: File('avatar.jpg').openRead(),
  meta: PhotoCreateMeta(table: 'users'),
);

final photoId = result['id'] as String;
```

`meta` ties the photo to a specific table and column in your schema. See
[Photo Tables](/schemas/photo-tables) for how to define columns that accept photos.

## Download a Photo

`get` returns a `Stream<List<int>>` so the bytes can be piped directly to a
file or an HTTP response without loading the entire image into memory:

```dart in:client
final stream = client.photos.get(id: photoId);

// Write to a file
final file = File('downloaded.jpg');
await file.openWrite().addStream(stream);
```

## Update a Photo

Replace the image for an existing photo ID:

```dart in:client
await client.photos.update(
  id: photoId,
  image: File('new_avatar.jpg').openRead(),
);
```

## Delete a Photo

```dart in:client
await client.photos.delete(id: photoId);
```

The record that references the photo is not automatically updated — clear or
nullify the photo column in the corresponding row after deleting.
