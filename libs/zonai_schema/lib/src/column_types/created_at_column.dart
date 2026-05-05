import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

extension CreatedAtColumnDefinition<S extends Schema<S>> on SchemaBuilder<S> {
  T createdAt<T extends DateTimeColumn?>(
    String name,
    Field<S, DateTime> field,
    DateTime? value,
  ) {
    return custom<DateTime, int>(
          DateTimeColumn.new,
          name,
          field,
          value,
          transformer: const CreatedAtTransformer(),
          sqlType: 'INTEGER',
          defaultValue: '${const CreatedAtTransformer().encode(.now())}',
        )
        as T;
  }
}

class CreatedAtTransformer extends ColumnTransformer<DateTime, int> {
  const CreatedAtTransformer();

  @override
  int encode(DateTime input) => input.millisecondsSinceEpoch;

  @override
  DateTime decode(int input) => DateTime.fromMillisecondsSinceEpoch(input);
}
