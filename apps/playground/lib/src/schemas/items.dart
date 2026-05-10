import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../ids.dart';

/// A simple persisted row (demo table for SQLite read/write).
class Item extends Collection<Item> {
  Item({
    ItemsId? id,
    required String body,
    String? description,
    int? status,
    DateTime? updatedAt,
  }) : id = $
           .id(
             'id',
             (s) => s.id,
             id,
             fromString: ItemsId.new,
             generate: ItemsId.generate,
           )
           .primaryKey(),
       body = $.text('body', (s) => s.body, body),
       description = $.text('description', (s) => s.description, description),
       status = $.integer('status', (s) => s.status, status),
       createdAt = $.createdAt('created_at', (s) => s.createdAt, .now()),
       updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt, updatedAt);

  final IdColumn<ItemsId> id;
  final TextColumn body;
  final TextColumn? description;
  final IntColumn? status;

  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;

  static const $ = SchemaBuilder<Item>();
}

final items = collection(
  'items',
  () => Item(
    id: ItemsId.generate(),
    body: fakes.text(),
    description: fakes.text(),
    status: fakes.integer(),
    updatedAt: fakes.dateTime(),
  ),
);
