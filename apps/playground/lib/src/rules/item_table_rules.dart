import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemTableRules main() => ItemTableRules();

final class ItemTableRules extends TableRules<ItemTable, Item> {
  ItemTableRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt) async {
    return true;
  }

  Future<bool> canUpdate(Jwt? jwt) async {
    return true;
  }

  Future<bool> canDelete(Jwt? jwt) async {
    return true;
  }

  Future<bool> canList(Jwt? jwt) async {
    return true;
  }

  @override
  Future<bool> canCreate(Jwt? jwt) async {
    return true;
  }
}
