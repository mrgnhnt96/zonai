import 'package:zonai_schema/zonai_schema.dart';

/// Minimal `_photos` table for Raindrop CLI schema introspection only.
final class IntrospectionPhotosTable extends PhotosTable {
  IntrospectionPhotosTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PhotoId.new,
        generate: PhotoId.generate,
      ),
      ownerId = $.id(
        'owner_id',
        (s) => s.ownerId,
        fromString: UnknownId.new,
        synthetic: const UnknownId('__photo_owner__'),
        generate: () => const UnknownId('__photo_owner__'),
        isPrimaryKey: false,
      ),
      ownerTable = $.text('owner_collection', (s) => s.ownerTable),
      collection = $.text('table', (s) => s.table),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      path = $.text('path', (s) => s.path),
      extension = $.text('extension', (s) => s.extension);

  @override
  PhotoEntry fromRow(RowReader read) {
    throw UnsupportedError('Introspection-only photos table');
  }

  final IdColumn<PhotoId> id;
  final IdColumn<UnknownId> ownerId;
  final TextColumn ownerTable;
  final TextColumn collection;
  final DateTimeColumn createdAt;
  final TextColumn path;
  final TextColumn extension;
}
