import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemRecordRules main() => ItemRecordRules();

class ItemRecordRules extends RecordRules<ItemTable, Item> {
  ItemRecordRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item record) async {
    return true;
  }

  @override
  Future<bool> canUpdate(Jwt? jwt, Item record) async {
    return true;
  }

  @override
  Future<bool> canDelete(Jwt? jwt, Item record) async {
    return true;
  }

  @override
  Future<bool> canCreate(Jwt? jwt, Item record) async {
    return true;
  }
}
