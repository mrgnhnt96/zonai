import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension UpdatedAtColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> updatedAt<W extends DateTime?>(String name, Field<S, W> field) {
    return custom<DateTime, int, W>(
      name,
      field,
      transformer: const UpdatedAtTransformer(),
      sqlType: 'INTEGER',
    );
  }
}

class UpdatedAtTransformer extends ColumnTransformer<DateTime, int> {
  const UpdatedAtTransformer();

  @override
  int encode(DateTime input) => input.millisecondsSinceEpoch;

  @override
  DateTime decode(int input) => DateTime.fromMillisecondsSinceEpoch(input);
}
