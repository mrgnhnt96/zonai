import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

/// A simple persisted row (demo table for SQLite read/write).
class Item extends Schema<Item> {
  Item({
    int? id,
    required String body,
    String? description,
    DateTime? createdAt,
  }) : id = $.integer('id', (s) => s.id, id).primaryKey(autoIncrement: true),
       body = $.text('body', (s) => s.body, body),
       description = $.text('description', (s) => s.description, description),
       createdAt = $.dateTime('created_at', (s) => s.createdAt, createdAt);

  final IntColumn? id;

  final TextColumn body;
  final TextColumn? description;

  final DateTimeColumn? createdAt;

  static const $ = SchemaBuilder<Item>();
}

final items = sqliteTable(
  'items',
  () => Item(
    id: fakes.primaryKey(),
    body: fakes.text(),
    description: fakes.text(),
    createdAt: fakes.dateTime(),
  ),
);
