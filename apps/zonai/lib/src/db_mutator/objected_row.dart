import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

class ObjectedRow {
  const ObjectedRow({required this.columns, required this.values});

  final List<String> columns;
  final List<Object?> values;

  Map<String, Object?> toMap() {
    return {for (var i = 0; i < columns.length; i++) columns[i]: values[i]};
  }

  @override
  String toString() {
    return '${toMap()}';
  }
}

extension TableMapOutX<T extends Schema<R>, R> on TableMeta<T, R> {
  Map<String, Object?> mapOut(R row) {
    return ObjectedRow(
      columns: columns.map((e) => e.name).toList(),
      values: this.values(row),
    ).toMap();
  }
}
