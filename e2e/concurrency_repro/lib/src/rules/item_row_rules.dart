import 'package:zonai_concurrency_repro/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemRowRules main() => ItemRowRules();

class ItemRowRules extends RowRules<ItemTable, Item> {
  ItemRowRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item row) async => true;

  /// Every row, as a filter. Row rules that check each row need a scope for
  /// `/db/count` to answer at all (#45); this one admits everything, so the
  /// count still covers the whole table while per-row checks keep running.
  @override
  Future<Where?> viewScope(Jwt? jwt) async => const NotNull('id');

  @override
  Future<bool> canUpdate(Jwt? jwt, Item before, Item after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Item row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Item row) async => true;
}
