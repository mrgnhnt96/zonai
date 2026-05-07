import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../schemas/ids.dart';

extension ItemsIdColumnDefinition<S extends Schema<S>> on SchemaBuilder<S> {
  T itemsId<T extends ItemsIdColumn?>(
    String name,
    Field<S, T> field,
    ItemsId value,
  ) {
    return custom<ItemsId, String, ItemsIdColumn, T>(
          ItemsIdColumn.new,
          name,
          field,
          value,
          transformer: const ItemsIdTransformer(),
          sqlType: 'TEXT',
        )
        as T;
  }
}

extension type ItemsIdColumn(ItemsId _)
    implements ColumnType<ItemsId>, ItemsId {}

class ItemsIdTransformer extends ColumnTransformer<ItemsId, String>
    with CreatePrimaryKey<ItemsId> {
  const ItemsIdTransformer();

  @override
  String encode(ItemsId input) => input.value;

  @override
  ItemsId decode(String input) => Id.fromJson(input) as ItemsId;

  @override
  ItemsId primaryKey() => ItemsId.generate();
}
