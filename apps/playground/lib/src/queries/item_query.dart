import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

class ItemQuery extends CollectionOperations<Item> with InsertReturning<Item> {
  ItemQuery() : super(items);
}

ItemQuery main() => ItemQuery();
