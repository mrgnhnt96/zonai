import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/column_types/create_primary_key.dart';

extension IdColumnDefinition<S> on SchemaBuilder<S> {
  T id<T extends IdColumn<Id>?, V extends Id?>(
    String name,
    Field<S, V> field, {
    required Id Function(String) fromString,
    required Id Function() generate,
    bool isPrimaryKey = true,
    Id? synthetic,
  }) {
    final c =
        custom(
              IdColumn.new,
              name,
              field,
              transformer: IdTransformer(
                fromString: fromString,
                generate: generate,
              ),
              sqlType: 'TEXT',
              synthetic: synthetic ?? generate(),
            )
            as T;

    if (isPrimaryKey) {
      return c.primaryKey() as T;
    }

    return c;
  }
}

extension type IdColumn<T extends Id>(T _) implements ColumnType<T>, Id {}

/// Wire type [Object] so [decode] accepts SQL strings and in-memory [Id]
/// values (e.g. some drivers / RETURNING rows surface bound Dart values).
class IdTransformer extends ColumnTransformer<Id, Object>
    with CreatePrimaryKey<Id> {
  IdTransformer({required this.fromString, required this.generate});

  final Id Function(String) fromString;
  final Id Function() generate;

  @override
  String encode(Id input) => input.value;

  @override
  Id decode(Object input) {
    return switch (input) {
      final Id id => id,
      final String s => fromString(s),
      _ => throw ArgumentError.value(
        input,
        'input',
        'Expected String or Id, got ${input.runtimeType}',
      ),
    };
  }

  @override
  Id primaryKey() => generate();
}

extension IdOperators on ColumnOf<Id> {
  /// String equals [value].
  SQL equals(String value) => SQL([$, Op.equals, value]);
}
