import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/types/jwt.dart';

class Extension<T extends Schema<T>> {
  Extension(this.schema);

  final T schema;

  Table<T> get table => Table.getFor(schema);
}

mixin CreateExtension<T extends Schema<T>> on Extension<T> {
  Future<void> beforeCreate(T object, Jwt? jwt) async {}
  Future<void> afterCreateSuccess(T row, Jwt? jwt) async {}
  Future<void> afterCreateError(Object error, Jwt? jwt) async {}
}

mixin UpdateExtension<T extends Schema<T>> on Extension<T> {
  Future<void> beforeUpdate(T row, Jwt? jwt) async {}
  Future<void> afterUpdateSuccess(T before, T after, Jwt? jwt) async {}
  Future<void> afterUpdateError(Object error, Jwt? jwt) async {}
}

mixin DeleteExtension<T extends Schema<T>> on Extension<T> {
  Future<void> beforeDelete(T row, Jwt? jwt) async {}
  Future<void> afterDeleteSuccess(T row, Jwt? jwt) async {}
  Future<void> afterDeleteError(Object error, Jwt? jwt) async {}
}

mixin AuthExtension<T extends Schema<T>> on Extension<T> {
  Future<void> onSignUp(T user, Jwt? jwt) async {}
  Future<void> onSignIn(T user, Jwt? jwt) async {}
  Future<void> onLogout(T user, Jwt? jwt) async {}
}
