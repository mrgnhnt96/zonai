import 'package:raindrop/raindrop.dart';

abstract class Collection<T> extends Schema<T> {
  Collection(super.$);

  ColumnType<dynamic> get id;
}
