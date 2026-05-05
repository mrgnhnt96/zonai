import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

extension UpdatedAtColumnDefinition<S extends Schema<S>> on SchemaBuilder<S> {
  T updatedAt<T extends DateTimeColumn?>(
    String name,
    Field<S, DateTime> field,
    DateTime? value,
  ) {
    return custom<DateTime, int>(
          DateTimeColumn.new,
          name,
          field,
          value,
          transformer: const UpdatedAtTransformer(),
          sqlType: 'INTEGER',
        )
        as T;
  }
}

class UpdatedAtTransformer extends ColumnTransformer<DateTime, int> {
  const UpdatedAtTransformer();

  @override
  int encode(DateTime input) => input.millisecondsSinceEpoch;

  @override
  DateTime decode(int input) => DateTime.fromMillisecondsSinceEpoch(input);
}
