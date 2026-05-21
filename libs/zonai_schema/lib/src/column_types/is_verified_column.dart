import 'package:raindrop/raindrop.dart';

extension IsVerifiedColumnDefinition<S> on SchemaBuilder<S> {
  T isVerified<T extends IsVerifiedColumn?>(String name, Field<S, bool> field) {
    return custom(
          IsVerifiedColumn.new,
          name,
          field,
          transformer: const IsVerifiedTransformer(),
          sqlType: 'INTEGER',
        )
        as T;
  }
}

extension type IsVerifiedColumn(bool _) implements ColumnType<bool>, bool {}

class IsVerifiedTransformer extends ColumnTransformer<bool, int> {
  const IsVerifiedTransformer();

  @override
  int encode(bool input) => input ? 1 : 0;

  @override
  bool decode(int input) => input == 1;
}
