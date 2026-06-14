import 'package:raindrop/raindrop.dart';

extension CreatedAtColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> createdAt<W extends DateTime?>(
    String name,
    Field<S, W> field,
  ) {
    return custom<DateTime, int, W>(
      name,
      field,
      transformer: const CreatedAtTransformer(),
      sqlType: 'INTEGER',
    );
  }
}

class CreatedAtTransformer extends ColumnTransformer<DateTime, int> {
  const CreatedAtTransformer();

  @override
  int encode(DateTime input) => input.millisecondsSinceEpoch;

  @override
  DateTime decode(int input) => DateTime.fromMillisecondsSinceEpoch(input);
}
