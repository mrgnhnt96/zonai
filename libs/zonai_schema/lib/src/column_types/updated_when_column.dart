import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension UpdatedWhenColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> updatedWhen<W extends DateTime?>(
    String name,
    Field<S, W> field, {
    required String watchColumn,
  }) {
    return custom<DateTime, int, W>(
      name,
      field,
      transformer: UpdatedWhenTransformer(watchColumn),
      sqlType: 'INTEGER',
    );
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
