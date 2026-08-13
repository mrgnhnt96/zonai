// Members of a row rules class over the playground's own `items` table, which
// the AI templates use as their worked example.
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ItemRowRules extends RowRules<ItemTable, Item> {
  ItemRowRules() : super(items);

  // <<body>>
}
