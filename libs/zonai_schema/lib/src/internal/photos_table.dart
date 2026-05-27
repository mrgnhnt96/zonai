import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/schemas/table.dart';

class PhotoEntry {
  PhotoEntry({
    required this.id,
    required this.ownerId,
    required this.ownerTable,
    required this.table,
    required this.path,
    required this.extension,
    required this.createdAt,
  });

  PhotoEntry.create({
    required this.id,
    required this.ownerId,
    required this.ownerTable,
    required this.table,
    required this.path,
    required this.extension,
  }) : createdAt = .now();

  final PhotoId id;
  final Id ownerId;
  final String ownerTable;
  final DateTime createdAt;
  final String table;
  final String path;
  final String extension;
}

class PhotoId implements Id {
  PhotoId(this.value);
  static PhotoId generate() => PhotoId(Id.generate('ph'));

  @override
  final String value;
}

abstract class PhotosTable extends Table<PhotoEntry> {
  PhotosTable(super.$);
}
