import 'package:zonai_schema/src/internal/tables/photos_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class PhotoOperations extends TableOperations<PhotosTable, PhotoEntry> {
  PhotoOperations() : super(photos);
}

PhotoOperations main() => PhotoOperations();
