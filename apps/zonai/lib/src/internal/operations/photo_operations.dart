import 'package:zonai/src/internal/photos_collection.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';
import 'package:zonai_schema/src/internal/photos_collection.dart'
    show PhotoEntry;

final class PhotoOperations
    extends CollectionOperations<PhotosCollection, PhotoEntry> {
  PhotoOperations() : super(photos);
}

PhotoOperations main() => PhotoOperations();
