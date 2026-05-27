import 'package:raindrop/raindrop.dart' hide Table;
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/column_types/create_primary_key.dart';

extension IdColumnDefinition<S> on SchemaBuilder<S> {
  T id<I extends Id, T extends IdColumn<I>?, V extends Object?>(
    String name,
    Field<S, V> field, {
    required I Function(String) fromString,
    required I Function() generate,
    bool isPrimaryKey = true,
    I? synthetic,
  }) {
    final c =
        custom<IdColumn<I>, I, Object, V>(
              IdColumn<I>.new,
              name,
              field,
              transformer: IdTransformer<I>(
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
class IdTransformer<I extends Id> extends ColumnTransformer<I, Object>
    with CreatePrimaryKey<I> {
  IdTransformer({required this.fromString, required this.generate});

  final I Function(String) fromString;
  final I Function() generate;

  @override
  String encode(I input) => input.value;

  @override
  I decode(Object input) {
    return switch (input) {
      final I id => id,
      final Id id => fromString(id.value),
      final String s => fromString(s),
      _ => throw ArgumentError.value(
        input,
        'input',
        'Expected String or Id, got ${input.runtimeType}',
      ),
    };
  }

  @override
  I primaryKey() => generate();
}

extension IdOperators<T extends Id> on ColumnOf<T> {
  /// String equals [value].
  SQL equals(T value) => SQL([$, Op.equals, value.value]);
}
