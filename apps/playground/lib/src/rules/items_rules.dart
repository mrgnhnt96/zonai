import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemRules main() => ItemRules();

class ItemRules extends Rules<Item> {
  ItemRules() : super(items);

  @override
  Future<bool> canView(Request request) async {
    return true;
  }
}
