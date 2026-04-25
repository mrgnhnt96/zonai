import 'package:zonai_playground/src/schemas/items.dart';
import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemRecordRules main() => ItemRecordRules();

class ItemRecordRules extends RecordRules<Item> {
  ItemRecordRules() : super(items);

  @override
  Future<Filter?> canView(Request request) async {
    return not(items.id.isNull());
  }
}
