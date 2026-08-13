// Members of the extension over the playground's own `items` table, which the
// internal docs use rather than an invented one.
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ItemExtensions extends Extension<Item> {
  ItemExtensions() : super(items);

  // <<body>>
}
