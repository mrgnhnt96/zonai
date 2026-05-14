import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemExtensions main() => ItemExtensions();

class ItemExtensions extends Extension<Item>
    with CreateExtension<Item>, UpdateExtension<Item>, DeleteExtension<Item> {
  ItemExtensions() : super(items);

  @override
  Future<void> beforeCreate(Item object, Jwt? jwt) async {
    logger.debug('EXTENSION beforeCreate');
  }

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    logger.warn('JWT: $jwt');
    final item = await get.one(
      collection: 'items',
      where: Eq('id', object.id),
      jwt: jwt,
    );

    if (item == null) {
      throw StateError('Failed to get item');
    }

    logger.warn('GOT Items IN EXTENSION!!!: $item');

    logger.debug('EXTENSION afterCreateSuccess');
  }

  @override
  Future<void> afterCreateError(Object error, Jwt? jwt) async {
    logger.debug('EXTENSION afterCreateError');
  }

  @override
  Future<void> beforeUpdate(Item object, Jwt? jwt) async {
    logger.debug('EXTENSION beforeUpdate');
  }

  @override
  Future<void> afterUpdateSuccess(Item before, Item after, Jwt? jwt) async {
    logger.debug('EXTENSION afterUpdateSuccess');
  }

  @override
  Future<void> afterUpdateError(Object error, Jwt? jwt) async {
    logger.debug('EXTENSION afterUpdateError');
  }

  @override
  Future<void> beforeDelete(Item object, Jwt? jwt) async {
    logger.debug('EXTENSION beforeDelete');
  }

  @override
  Future<void> afterDeleteSuccess(Item object, Jwt? jwt) async {
    logger.debug('EXTENSION afterDeleteSuccess');
  }

  @override
  Future<void> afterDeleteError(Object error, Jwt? jwt) async {
    logger.debug('EXTENSION afterDeleteError');
  }
}
