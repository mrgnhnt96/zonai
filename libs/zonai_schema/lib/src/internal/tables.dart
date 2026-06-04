import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/internal/abusers_table.dart';
import 'package:zonai_schema/src/internal/introspection_tables.dart';
import 'package:zonai_schema/src/internal/photos_table.dart';

/// Ensures [photos] is initialized for Raindrop schema introspection (e.g. CLI
/// `generate` against playground schemas that use `$.photo`).
void ensureInternalTablesForIntrospection() {
  if (_photosInitialized) return;
  setupInternalTables(photos: table('_photos', IntrospectionPhotosTable.new));
}

void setupInternalTables({PhotosTable? photos, AbusersTable? abusers}) {
  if (photos != null) {
    _photos = photos;
    _photosInitialized = true;
  }

  if (abusers != null) {
    _abusers = abusers;
  }
}

var _photosInitialized = false;

late final PhotosTable _photos;
PhotosTable get photos {
  if (!_photosInitialized) {
    ensureInternalTablesForIntrospection();
  }
  return _photos;
}

late final AbusersTable _abusers;
AbusersTable get abusers => _abusers;
