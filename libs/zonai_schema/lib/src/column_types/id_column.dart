import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/column_types/create_primary_key.dart';

extension IdColumnDefinition<S extends Schema<S>> on SchemaBuilder<S> {
  T id<T extends IdColumn<Id>?>(
    String name,
    Field<S, T> field,
    Id? value, {
    required Id Function(String) fromString,
    required Id Function() generate,
    bool isPrimaryKey = true,
  }) {
    final column =
        custom<Id, String, IdColumn<Id>, T>(
              IdColumn.new,
              name,
              field,
              value ?? generate(),
              transformer: IdTransformer(
                fromString: fromString,
                generate: generate,
              ),
              sqlType: 'TEXT',
            )
            as T;

    if (isPrimaryKey) {
      return column.primaryKey() as T;
    }

    return column;
  }
}

extension type IdColumn<T extends Id>(T _) implements ColumnType<T>, Id {}

class IdTransformer extends ColumnTransformer<Id, String>
    with CreatePrimaryKey<Id> {
  IdTransformer({required this.fromString, required this.generate});

  final Id Function(String) fromString;
  final Id Function() generate;

  @override
  String encode(Id input) => input.value;

  @override
  Id decode(String input) => fromString(input);

  @override
  Id primaryKey() => generate();
}

extension IdOperators on ColumnOf<Id> {
  /// String equals [value].
  SQL equals(String value) => SQL([$, Op.equals, value]);
}
