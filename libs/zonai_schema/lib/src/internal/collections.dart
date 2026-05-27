import 'package:zonai_schema/src/internal/photos_collection.dart';

void setupInternalCollections({PhotosCollection? photos}) {
  if (photos != null) {
    _photos = photos;
  }
}

late final PhotosCollection _photos;

PhotosCollection get photos => _photos;
