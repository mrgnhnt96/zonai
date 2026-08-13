// Stand-in for the `items` table the AI templates use as their worked example.
//
// The playground has an `items` table of its own, but it is the playground's --
// no owner column, because nothing there needs one. The templates teach an
// ownership rule, so the stand-in carries `ownerId`, as an `UnknownId` rather
// than a `String`: that is what `Jwt.userId` is, and comparing an ID to a bare
// `String` is silently always false. See tasks.dart for the general rule about
// these fixtures.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Item {
  const Item({
    required this.id,
    required this.body,
    required this.description,
    required this.ownerId,
    required this.createdAt,
  });

  final ItemsId id;
  final String body;
  final String description;
  final UnknownId ownerId;
  final DateTime createdAt;
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
      ownerId = $.text('owner_id', (s) => s.ownerId.value),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  @override
  Item fromRow(RowReader read) => Item(
    id: read(id),
    body: read(body),
    description: read(description),
    ownerId: UnknownId(read(ownerId)),
    createdAt: read(createdAt),
  );

  final IdColumn<ItemsId> id;
  final TextColumn body;
  final TextColumn description;
  final TextColumn ownerId;
  final DateTimeColumn createdAt;
}

final items = table('items', ItemTable.new);
