import 'package:zonai_schema/src/request.dart';

class Extension<T> {
  Extension(this.schema);

  final T schema;
}

mixin CreateExtension<T> on Extension<T> {
  Future<void> beforeCreate(Request request) async {}
  Future<void> onCreate(Request request, Future<T> create(T)) async {}
  Future<void> afterCreateSuccess(Request request, T row) async {}
  Future<void> afterCreateError(Request request, Object error) async {}
}

mixin UpdateExtension<T> on Extension<T> {
  Future<void> beforeUpdate(Request request, T row) async {}
  Future<void> onUpdate(Request request, Future<T> update(T)) async {}
  Future<void> afterUpdateSuccess(Request request, T row) async {}
  Future<void> afterUpdateError(Request request, Object error) async {}
}

mixin DeleteExtension<T> on Extension<T> {
  Future<void> beforeDelete(Request request, T row) async {}
  Future<void> onDelete(Request request, Future<void> delete(T)) async {}
  Future<void> afterDeleteSuccess(Request request) async {}
  Future<void> afterDeleteError(Request request, Object error) async {}
}
