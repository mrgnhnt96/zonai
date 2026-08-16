import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemTableRules main() => ItemTableRules();

/// `items` carries no owner column, so there is no ownership test to make --
/// the honest rule for a table shaped like this is "public to read, signed-in
/// to write", and the row rules cannot narrow it further.
///
/// If this were a real collection it would want an owner column and the
/// author pattern in `post_row_rules.dart`.
final class ItemTableRules extends TableRules<ItemTable, Item> {
  ItemTableRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt != null;
}
