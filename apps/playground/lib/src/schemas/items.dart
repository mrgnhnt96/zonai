import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

import '../column_types/column_types.dart';
import 'ids.dart';

/// A simple persisted row (demo table for SQLite read/write).
class Item extends Schema<Item> {
  Item({
    ItemsId? id,
    required String body,
    String? description,
    int? status,
    DateTime? createdAt,
  }) : id = $.itemsId('id', (s) => s.id, id).primaryKey(),
       body = $.text('body', (s) => s.body, body),
       description = $.text('description', (s) => s.description, description),
       status = $.integer('status', (s) => s.status, status),
       createdAt = $.dateTime('created_at', (s) => s.createdAt, createdAt);

  final ItemsIdColumn? id;
  final TextColumn body;
  final TextColumn? description;
  final IntColumn? status;

  final DateTimeColumn? createdAt;

  static const $ = SchemaBuilder<Item>();
}

final items = sqliteTable(
  'items',
  () => Item(
    id: ItemsId.generate(),
    body: fakes.text(),
    description: fakes.text(),
    status: fakes.integer(),
    createdAt: fakes.dateTime(),
  ),
);
