import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemRecordRules main() => ItemRecordRules();

class ItemRecordRules extends RecordRules<Item> {
  ItemRecordRules() : super(items);

  @override
  Future<bool> canView(Request request, Item record) async {
    return true;
  }
}
