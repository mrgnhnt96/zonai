import 'package:raindrop/raindrop.dart';

abstract class Table<T> extends Schema<T> {
  Table(super.$);

  ColumnType<dynamic> get id;
}
