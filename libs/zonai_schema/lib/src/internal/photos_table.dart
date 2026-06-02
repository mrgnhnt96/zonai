import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/column_types/id_column.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/schemas/table.dart';

class PhotoEntry {
  const PhotoEntry({
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
  PhotoId(this.value) {
    if (!value.endsWith(_suffix)) {
      throw ArgumentError.value(value, 'value', 'Value must end with $_suffix');
    }
  }

  factory PhotoId.fromJson(String value) => PhotoId(value);

  static PhotoId generate() => PhotoId(Id.generate(_suffix));

  static const _suffix = 'ph';

  String toJson() => value;

  @override
  final String value;
}

abstract class PhotosTable extends Table<PhotoEntry> {
  PhotosTable(super.$);

  IdColumn<PhotoId> get id;
  IdColumn<UnknownId> get ownerId;
  TextColumn get ownerTable;
  TextColumn get collection;
  DateTimeColumn get createdAt;
  TextColumn get path;
  TextColumn get extension;
}
