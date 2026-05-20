import 'package:raindrop/raindrop.dart';

/// Dart [Enum] stored as TEXT (enum [.name] on the wire by default).
extension type EnumListColumn<E extends Enum>(List<E> _)
    implements ColumnType<List<E>> {}

extension EnumListColumnDefinition<S> on SchemaBuilder<S> {
  T enumList<E extends Enum, T extends EnumListColumn<E>?, W extends Object?>(
    String name,
    List<E> values,
    Field<S, List<E>> field, {
    String Function(E value)? toWire,
    E Function(String wire)? fromWire,
  }) {
    return custom<EnumListColumn<E>, List<E>, Object, List<E>>(
          EnumListColumn<E>.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: EnumListTransformer<E>(
            values: values,
            toWire: toWire,
            fromWire: fromWire,
          ),
          synthetic: [],
        )
        as T;
  }
}

class EnumListTransformer<E extends Enum>
    extends ColumnTransformer<List<E>, Object> {
  EnumListTransformer({
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
  String encode(List<E> input) {
    if (!values.contains(input)) {
      throw ArgumentError.value(
        input,
        'input',
        'Invalid value for enum $values',
      );
    }
    return input.map(toWire).join(',');
  }

  E _decodeSingle(String input) {
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
    };
  }

  @override
  List<E> decode(Object input) {
    return switch (input) {
      final List<E> values => values,
      final String input => input.split(',').map(_decodeSingle).toList(),
      _ => throw ArgumentError.value(
        input,
        'input',
        'Expected List<E> or String, got ${input.runtimeType}',
      ),
    };
  }
}
