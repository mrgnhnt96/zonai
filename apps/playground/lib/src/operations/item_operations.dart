import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ItemOperations extends CollectionOperations<Item> {
  ItemOperations() : super(items);
}

ItemOperations main() => ItemOperations();
