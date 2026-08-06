import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/column_types/create_primary_key.dart';

extension IdColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<V> id<I extends Id, V extends I?>(
    String name,
    V Function(S) field, {
    required I Function(String) fromString,
    required I Function() generate,
    bool isPrimaryKey = true,
    I? synthetic,
  }) {
    var column = custom<I, Object, V>(
      name,
      field,
      transformer: IdTransformer<I>(
        fromString: fromString,
        generate: generate,
        synthetic: synthetic,
      ),
      sqlType: 'TEXT',
    );

    if (isPrimaryKey) {
      column = column.primaryKey();
    }

    return column;
  }
}

typedef IdColumn<T extends Id> = ColumnType<T>;

/// Wire type [Object] so [decode] accepts SQL strings and in-memory [Id]
/// values (e.g. some drivers / RETURNING rows surface bound Dart values).
class IdTransformer<I extends Id> extends ColumnTransformer<I, Object>
    with CreatePrimaryKey<I> {
  IdTransformer({
    required this.fromString,
    required this.generate,
    this.synthetic,
  });

  final I Function(String) fromString;
  final I Function() generate;
  final I? synthetic;

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
  I primaryKey() => synthetic ?? generate();
}

extension IdOperators<T extends Id> on ColumnOf<T> {
  /// Compares against another [Id] value, or another id-typed column — e.g.
  /// a join condition: `posts.authorId.equals(authors.id)`.
  SQL equals(ColumnOr<T> value) {
    final operand = switch (value) {
      final Id id => id.value,
      final other => other,
    };
    return SQL([this, Op.equals, operand]);
  }
}
