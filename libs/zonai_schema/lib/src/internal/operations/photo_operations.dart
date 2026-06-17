import 'package:zonai_schema/src/internal/tables/photos_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';
import 'package:zonai_schema/src/internal/photos_table.dart' show PhotoEntry;

final class PhotoOperations extends TableOperations<PhotosTable, PhotoEntry> {
  PhotoOperations() : super(photos);
}

PhotoOperations main() => PhotoOperations();
