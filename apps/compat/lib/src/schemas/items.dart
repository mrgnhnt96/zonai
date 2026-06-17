import 'package:zonai_schema/zonai_schema.dart';

import '../ids.dart';

class Item {
  Item({
    required this.id,
    required this.body,
    required this.createdAt,
    this.updatedAt,
  });

  final ItemsId id;
  final String body;
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
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Item fromRow(RowReader read) {
    return Item(
      id: read(id),
      body: read(body),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<ItemsId> id;
  final TextColumn body;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final items = table('items', ItemTable.new);
