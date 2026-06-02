import 'package:raindrop/raindrop.dart';

extension IsVerifiedColumnDefinition<S> on SchemaBuilder<S> {
  T isVerified<T extends IsVerifiedColumn?, W extends bool?>(
    String name,
    Field<S, W> field,
  ) {
    return custom<IsVerifiedColumn, bool, Object, W>(
          IsVerifiedColumn.new,
          name,
          field,
          transformer: const IsVerifiedTransformer(),
          sqlType: 'INTEGER',
          defaultValue: '0',
        )
        as T;
  }
}

extension type IsVerifiedColumn(bool _) implements ColumnType<bool>, bool {}

/// Wire type [Object] so [decode] accepts SQL integers and in-memory [bool]
/// values (e.g. some drivers / RETURNING rows surface bound Dart values).
class IsVerifiedTransformer extends ColumnTransformer<bool, Object> {
  const IsVerifiedTransformer();

  @override
  int encode(bool input) => input ? 1 : 0;

  @override
  bool decode(Object input) {
    return switch (input) {
      bool value => value,
      int value => value == 1,
      _ => throw ArgumentError.value(
        input,
        'input',
        'Expected bool or int, got ${input.runtimeType}',
      ),
    };
  }
}
