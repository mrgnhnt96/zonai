import 'package:zonai_stress_fixture/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Item {
  Item({
    required this.id,
    required this.name,
    required this.createdAt,
    this.updatedAt,
  });

  final ItemsId id;
  final String name;
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
      name = $.text('name', (s) => s.name),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Item fromRow(RowReader read) {
    return Item(
      id: read(id),
      name: read(name),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<ItemsId> id;
  final TextColumn name;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final items = table('items', ItemTable.new);
