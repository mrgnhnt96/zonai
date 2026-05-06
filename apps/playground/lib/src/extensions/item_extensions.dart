import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemExtensions main() => ItemExtensions();

class ItemExtensions extends Extension<Item>
    with CreateExtension<Item>, UpdateExtension<Item>, DeleteExtension<Item> {
  ItemExtensions() : super(items);

  @override
  Future<void> beforeCreate(Item object) async {
    logger.debug('EXTENSION beforeCreate');
  }

  @override
  Future<void> afterCreateSuccess(Item object) async {
    logger.debug('EXTENSION afterCreateSuccess');
  }

  @override
  Future<void> afterCreateError(Object error) async {
    logger.debug('EXTENSION afterCreateError');
  }

  @override
  Future<void> beforeUpdate(Item object) async {
    logger.debug('EXTENSION beforeUpdate');
  }

  @override
  Future<void> afterUpdateSuccess(Item before, Item after) async {
    logger.debug('EXTENSION afterUpdateSuccess');
  }

  @override
  Future<void> afterUpdateError(Object error) async {
    logger.debug('EXTENSION afterUpdateError');
  }

  @override
  Future<void> beforeDelete(Item object) async {
    logger.debug('EXTENSION beforeDelete');
  }

  @override
  Future<void> afterDeleteSuccess(Item object) async {
    logger.debug('EXTENSION afterDeleteSuccess');
  }

  @override
  Future<void> afterDeleteError(Object error) async {
    logger.debug('EXTENSION afterDeleteError');
  }
}
