// Members of a table's rate-limit file -- the per-operation policy overrides.
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ItemRateLimits extends TableRateLimits<ItemTable, Item> {
  ItemRateLimits() : super(items);

  // <<body>>
}
