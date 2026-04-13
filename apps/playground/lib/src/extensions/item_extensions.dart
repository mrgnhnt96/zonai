import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemExtensions main() => ItemExtensions();

class ItemExtensions extends Extension<Item> with CreateExtension<Item> {
  ItemExtensions() : super(items);

  @override
  Future<void> onCreate(Request request, Future<Item> create(Item)) async {}
}
