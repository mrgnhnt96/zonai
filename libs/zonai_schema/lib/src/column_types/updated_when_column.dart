import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

extension UpdatedWhenColumnDefinition<S> on SchemaBuilder<S> {
  T updatedWhen<T extends DateTimeColumn?, W extends DateTime?>(
    String name,
    W Function(S) field, {
    required String watchColumn,
  }) {
    return custom<DateTimeColumn, DateTime, int, W>(
          DateTimeColumn.new,
          name,
          field,
          transformer: UpdatedWhenTransformer(watchColumn),
          sqlType: 'INTEGER',
        )
        as T;
  }
}

/// Marks a datetime column that auto-updates whenever [watchedColumn] is
/// included in an update operation.
class UpdatedWhenTransformer extends ColumnTransformer<DateTime, int> {
  const UpdatedWhenTransformer(this.watchedColumn);

  final String watchedColumn;

  @override
  int encode(DateTime input) => input.millisecondsSinceEpoch;

  @override
  DateTime decode(int input) => DateTime.fromMillisecondsSinceEpoch(input);
}
