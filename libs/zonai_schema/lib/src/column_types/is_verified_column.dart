import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension IsVerifiedColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> isVerified<W extends bool?>(
    String name,
    Field<S, W> field, {
    String? defaultValue,
  }) {
    return custom<bool, Object, W>(
      name,
      field,
      transformer: const IsVerifiedTransformer(),
      sqlType: 'INTEGER',
      defaultValue: defaultValue,
    );
  }
}

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
