import 'package:zonai_schema/zonai_schema.dart';

class PhotoEntry {
  PhotoEntry({
    required this.id,
    required this.ownerId,
    required this.ownerCollection,
    required this.collection,
    required this.path,
    required this.extension,
  }) : createdAt = .now();

  PhotoEntry._({
    required this.id,
    required this.ownerId,
    required this.ownerCollection,
    required this.collection,
    required this.createdAt,
    required this.path,
    required this.extension,
  });

  final PhotoId id;
  final Id ownerId;
  final String ownerCollection;
  final DateTime createdAt;
  final String collection;
  final String path;
  final String extension;
}

class PhotoId implements Id {
  PhotoId(this.value);
  static PhotoId generate() => PhotoId(Id.generate('ph'));

  @override
  final String value;
}

class PhotosCollection extends Collection<PhotoEntry> {
  PhotosCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PhotoId.new,
        generate: PhotoId.generate,
      ),
      ownerId = $.id(
        'owner_id',
        (s) => s.ownerId,
        fromString: UnknownId.new,
        synthetic: const UnknownId('__PHOTO_OWNER__'),
        generate: () => throw Exception('Owner ID is required for photos'),
        isPrimaryKey: false,
      ),
      ownerCollection = $.text('owner_collection', (s) => s.ownerCollection),
      collection = $.text('collection', (s) => s.collection),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      path = $.text('path', (s) => s.path),
      extension = $.text('extension', (s) => s.extension);

  @override
  PhotoEntry fromRow(RowReader read) {
    return PhotoEntry._(
      id: read(id),
      ownerId: read(ownerId),
      ownerCollection: read(ownerCollection),
      collection: read(collection),
      createdAt: read(createdAt),
      path: read(path),
      extension: read(extension),
    );
  }

  final IdColumn<PhotoId> id;
  final IdColumn<UnknownId> ownerId;
  final TextColumn ownerCollection;
  final TextColumn collection;
  final DateTimeColumn createdAt;
  final TextColumn path;
  final TextColumn extension;
}

final photos = collection('_photos', PhotosCollection.new);
