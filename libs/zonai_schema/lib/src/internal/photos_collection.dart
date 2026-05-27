import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/schemas/collection.dart';

class PhotoEntry {
  PhotoEntry({
    required this.id,
    required this.ownerId,
    required this.ownerCollection,
    required this.collection,
    required this.path,
    required this.extension,
    required this.createdAt,
  });

  PhotoEntry.create({
    required this.id,
    required this.ownerId,
    required this.ownerCollection,
    required this.collection,
    required this.path,
    required this.extension,
  }) : createdAt = .now();

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

abstract class PhotosCollection extends Collection<PhotoEntry> {
  PhotosCollection(super.$);
}
