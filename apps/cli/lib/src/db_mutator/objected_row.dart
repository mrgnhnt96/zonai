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
