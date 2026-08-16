import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemRowRules main() => ItemRowRules();

/// See `item_table_rules.dart`: with no owner column on `items`, the row layer
/// has nothing to decide beyond "is there a caller at all", and the table
/// layer has already asked that for writes.
class ItemRowRules extends RowRules<ItemTable, Item> {
  ItemRowRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Item row) async => jwt != null;

  @override
  Future<bool> canUpdate(Jwt? jwt, Item before, Item after) async =>
      jwt != null;

  @override
  Future<bool> canDelete(Jwt? jwt, Item row) async => jwt != null;
}
