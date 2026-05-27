import 'package:zonai/src/internal/photos_collection.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';

final class PhotoOperations
    extends CollectionOperations<PhotosCollection, PhotoEntry> {
  PhotoOperations() : super(photos);
}

PhotoOperations main() => PhotoOperations();
