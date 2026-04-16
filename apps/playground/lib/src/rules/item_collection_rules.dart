import 'package:raindrop/raindrop.dart';
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

class ItemRecordRules extends RecordRules<Item> {
  ItemRecordRules() : super(items);

  @override
  Future<Filter?> canView(Request request) async {
    return not(items.id.isNull()) & items.description.like('%test%');
  }
}
