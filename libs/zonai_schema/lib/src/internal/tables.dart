import 'package:zonai_schema/src/internal/photos_table.dart';

void setupInternalTables({PhotosTable? photos}) {
  if (photos != null) {
    _photos = photos;
  }
}

late final PhotosTable _photos;

PhotosTable get photos => _photos;
