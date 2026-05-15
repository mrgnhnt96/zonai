import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../ids.dart';

/// A simple persisted row (demo table for SQLite read/write).
class Item {
  Item({
    required this.id,
    required this.body,
    required this.createdAt,
    this.description,
    this.status,
    this.updatedAt,
  });

  final ItemsId id;
  final String body;
  final String? description;
  final int? status;

  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class ItemCollection extends Collection<Item> {
  ItemCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: ItemsId.new,
        generate: ItemsId.generate,
      ),
      body = $.text('body', (s) => s.body),
      description = $.text('description', (s) => s.description),
      status = $.integer('status', (s) => s.status),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Item fromRow(RowReader read) {
    return Item(
      id: read(id),
      body: read(body),
      description: read(description),
      status: read(status),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<ItemsId> id;
  final TextColumn body;
  final TextColumn? description;
  final IntColumn? status;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;
}

final items = collection('items', ItemCollection.new);
