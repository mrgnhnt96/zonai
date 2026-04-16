import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemCollectionRules main() => ItemCollectionRules();

class ItemCollectionRules extends CollectionRules<Item> {
  ItemCollectionRules() : super(items);

  @override
  Future<bool> canView(Request request) async {
    return true;
  }
}
