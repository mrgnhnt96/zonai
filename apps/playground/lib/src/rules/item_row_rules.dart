import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemRowRules main() => ItemRowRules();

class ItemRowRules extends RowRules<ItemTable, Item> {
  ItemRowRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item row) async {
    return true;
  }

  @override
  Future<bool> canUpdate(Jwt? jwt, Item row) async {
    return true;
  }

  @override
  Future<bool> canDelete(Jwt? jwt, Item row) async {
    return true;
  }

  @override
  Future<bool> canCreate(Jwt? jwt, Item row) async {
    return true;
  }
}
