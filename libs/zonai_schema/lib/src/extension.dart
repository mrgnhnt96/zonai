import 'package:raindrop/raindrop.dart';

class Extension<T extends Schema<T>> {
  Extension(this.schema);

  final T schema;

  Table<T> get table => Table.getFor(schema);
}

mixin CreateExtension<T extends Schema<T>> on Extension<T> {
  Future<void> beforeCreate(T object) async {}
  Future<void> afterCreateSuccess(T row) async {}
  Future<void> afterCreateError(Object error) async {}
}

mixin UpdateExtension<T extends Schema<T>> on Extension<T> {
  Future<void> beforeUpdate(T row) async {}
  Future<void> afterUpdateSuccess(T before, T after) async {}
  Future<void> afterUpdateError(Object error) async {}
}

mixin DeleteExtension<T extends Schema<T>> on Extension<T> {
  Future<void> beforeDelete(T row) async {}
  Future<void> afterDeleteSuccess(T row) async {}
  Future<void> afterDeleteError(Object error) async {}
}
