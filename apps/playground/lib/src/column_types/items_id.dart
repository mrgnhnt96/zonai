import 'package:raindrop/raindrop.dart';

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

class ItemsIdTransformer extends ColumnTransformer<ItemsId, String> {
  const ItemsIdTransformer();

  @override
  String encode(ItemsId input) => input.value;

  @override
  ItemsId decode(String input) => Id.fromJson(input) as ItemsId;
}
