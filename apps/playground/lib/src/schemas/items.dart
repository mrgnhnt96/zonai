import 'package:zonai_schema/zonai_schema.dart';

import '../ids.dart';

/// A simple persisted row (demo table for SQLite read/write).
class Item {
  Item({
    required this.id,
    required this.body,
    required this.createdAt,
    this.description,
    this.image,
    this.status,
    this.updatedAt,
  });

  final ItemsId id;
  final String body;
  final String? description;
  final PhotoId? image;
  final int? status;

  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class ItemTable extends Table<Item> {
  ItemTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: ItemsId.new,
        generate: ItemsId.generate,
      ),
      body = $.text('body', (s) => s.body),
      description = $.text('description', (s) => s.description),
      image = $.photo('image', (s) => s.image),
      status = $.integer('status', (s) => s.status),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Item fromRow(RowReader read) {
    return Item(
      id: read(id),
      body: read(body),
      description: read(description),
      image: read(image),
      status: read(status),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<ItemsId> id;
  final TextColumn body;
  final ColumnType<String?> description;
  final ColumnType<PhotoId?> image;
  final ColumnType<int?> status;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final items = table('items', ItemTable.new);
