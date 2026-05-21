import 'package:raindrop/raindrop.dart';

/// Dart [Enum] stored as TEXT (enum [.name] on the wire by default).
extension type EnumColumn<E extends Enum>(E _) implements ColumnType<E> {}

extension EnumColumnDefinition<S> on SchemaBuilder<S> {
  T enumerator<E extends Enum, T extends EnumColumn<E>?, W extends Object?>(
    String name,
    List<E> values,
    Field<S, W> field, {
    String Function(E value)? toWire,
    E Function(String wire)? fromWire,
  }) {
    return custom<EnumColumn<E>, E, Object, W>(
          EnumColumn<E>.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: EnumTransformer<E>(
            values: values,
            toWire: toWire,
            fromWire: fromWire,
          ),
          synthetic: values.first,
        )
        as T;
  }
}

class EnumTransformer<E extends Enum> extends ColumnTransformer<E, Object> {
  EnumTransformer({
    required this.values,
    String Function(E value)? toWire,
    E Function(String wire)? fromWire,
  }) : toWire = toWire ?? ((e) => e.name),
       _byWire = {
         for (final value in values) (toWire ?? ((e) => e.name))(value): value,
       },
       _fromWire = fromWire;

  final List<E> values;
  final String Function(E) toWire;
  final Map<String, E> _byWire;
  final E Function(String)? _fromWire;

  @override
  String encode(E input) {
    if (!values.contains(input)) {
      throw ArgumentError.value(
        input,
        'input',
        'Invalid value for enum $values',
      );
    }
    return toWire(input);
  }

  @override
  E decode(Object input) {
    return switch (input) {
      final E value when values.contains(value) => value,
      final String wire =>
        _fromWire?.call(wire) ??
            _byWire[wire] ??
            (throw ArgumentError.value(
              wire,
              'wire',
              'Invalid value for enum $values',
            )),
      _ => throw ArgumentError.value(
        input,
        'input',
        'Expected $E or String, got ${input.runtimeType}',
      ),
    };
  }
}

// TODO: Add more operators for this and other columns
extension EnumOperators<E extends Enum> on ColumnOf<E> {
  /// String equals [value] using the column's wire encoding (enum [.name] by default).
  SQL equals(E value) {
    final wire = switch (ColumnType.lookup(this)?.transformer) {
      EnumTransformer<E>(:final toWire) => toWire(value),
      _ => value.name,
    };
    return SQL([$, Op.equals, wire]);
  }
}
