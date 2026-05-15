import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

extension CreatedAtColumnDefinition<S> on SchemaBuilder<S> {
  T createdAt<T extends DateTimeColumn?>(
    String name,
    Field<S, DateTime> field,
  ) {
    return custom(
          DateTimeColumn.new,
          name,
          field,
          transformer: const CreatedAtTransformer(),
          sqlType: 'INTEGER',
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
