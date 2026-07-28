import 'package:zonai_concurrency_repro/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemTableRules main() => ItemTableRules();

final class ItemTableRules extends TableRules<ItemTable, Item> {
  ItemTableRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
