import 'package:zonai_schema/src/internal/abusers_table.dart';
import 'package:zonai_schema/src/internal/photos_table.dart';

void setupInternalTables({PhotosTable? photos, AbusersTable? abusers}) {
  if (photos != null) {
    _photos = photos;
  }

  if (abusers != null) {
    _abusers = abusers;
  }
}

late final PhotosTable _photos;
PhotosTable get photos => _photos;

late final AbusersTable _abusers;
AbusersTable get abusers => _abusers;
