import 'package:zonai_schema/zonai_schema.dart';

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

class PhotosTable extends Table<PhotoEntry> {
  PhotosTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PhotoId.new,
        generate: PhotoId.generate,
      ),
      ownerId = $.id<UnknownId, UnknownId>(
        'owner_id',
        (s) => UnknownId(s.ownerId.value),
        fromString: UnknownId.new,
        synthetic: const UnknownId('__PHOTO_OWNER__'),
        generate: () => const UnknownId('__PHOTO_OWNER__'),
        isPrimaryKey: false,
      ),
      ownerTable = $.text('owner_collection', (s) => s.ownerTable),
      collection = $.text('table', (s) => s.table),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      path = $.text('path', (s) => s.path),
      extension = $.text('extension', (s) => s.extension);

  @override
  PhotoEntry fromRow(RowReader read) {
    return PhotoEntry(
      id: read(id),
      ownerId: read(ownerId),
      ownerTable: read(ownerTable),
      table: read(collection),
      createdAt: read(createdAt),
      path: read(path),
      extension: read(extension),
    );
  }

  final IdColumn<PhotoId> id;
  final IdColumn<UnknownId> ownerId;
  final TextColumn ownerTable;
  final TextColumn collection;
  final DateTimeColumn createdAt;
  final TextColumn path;
  final TextColumn extension;
}

final photos = table('_photos', PhotosTable.new);
