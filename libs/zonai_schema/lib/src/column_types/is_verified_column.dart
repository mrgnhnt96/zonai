import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

extension IsVerifiedColumnDefinition<S> on SchemaBuilder<S> {
  T isVerified<T extends IsVerifiedColumn?>(
    String name,
    Field<S, bool?> field,
  ) {
    return boolean(name, field);
  }
}

extension type IsVerifiedColumn(bool _) implements ColumnType<bool>, bool {}

class IsVerifiedTransformer extends ColumnTransformer<bool, bool> {
  const IsVerifiedTransformer();

  @override
  bool encode(bool input) => input;

  @override
  bool decode(bool input) => input;
}
