import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_db/schemas/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../column_types/column_types.dart';

/// A simple persisted row (demo table for SQLite read/write).
class Item extends Schema<Item> {
  Item({
    required String body,
    String? description,
    int? status,
    DateTime? updatedAt,
  }) : id = $.itemsId('id', (s) => s.id, ItemsId.generate()).primaryKey(),
       body = $.text('body', (s) => s.body, body),
       description = $.text('description', (s) => s.description, description),
       status = $.integer('status', (s) => s.status, status),
       updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt, updatedAt),
       createdAt = $.createdAt('created_at', (s) => s.createdAt, .now());

  final ItemsIdColumn id;
  final TextColumn body;
  final TextColumn? description;
  final IntColumn? status;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;

  static const $ = SchemaBuilder<Item>();
}

final items = sqliteTable(
  'items',
  () => Item(
    body: fakes.text(),
    description: fakes.text(),
    status: fakes.integer(),
    updatedAt: fakes.dateTime(),
  ),
);
