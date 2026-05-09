import 'package:raindrop/raindrop.dart';
import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

extension IdColumnDefinition<S extends Schema<S>> on SchemaBuilder<S> {
  T id<T extends IdColumn<Id>?>(
    String name,
    Field<S, T> field,
    Id? value, {
    required Id Function(String) fromString,
    required Id Function() generate,
  }) {
    return custom<Id, String, IdColumn<Id>, T>(
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
