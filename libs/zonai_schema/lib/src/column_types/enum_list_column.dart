import 'dart:convert';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension EnumListColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> enumList<E extends Enum, W extends List<E>?>(
    String name,
    List<E> values,
    Field<S, W> field, {
    String Function(E value)? toWire,
    E Function(String wire)? fromWire,
  }) {
    return custom<List<E>, Object, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: EnumListTransformer<E>(
        values: values,
        toWire: toWire,
        fromWire: fromWire,
      ),
    );
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
    final items = _enumItems(input);
    return items.map(toWire).join(',');
  }

  List<E> _enumItems(List<E> input) {
    if (input.isEmpty) return input;
    if (input.every(values.contains)) return input;
    return decode(input);
  }

  E _decodeSingle(Object input) {
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
        'Invalid value for enum $values',
      ),
    };
  }

  @override
  List<E> decode(Object input) {
    if (input is String) {
      if (input.isEmpty) {
        return [];
      }
      final trimmed = input.trim();
      if (trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) {
            return decode(decoded);
          }
        } on FormatException {
          // fall through to comma split
        }
      }
      return input.split(',').map(_decodeSingle).toList();
    }

    if (input is List) {
      final items = _flattenList(input);
      if (items.isNotEmpty &&
          items.every((e) => e is E && values.contains(e))) {
        return List<E>.from(items.cast<E>());
      }
      return [
        for (final item in items)
          if (item != null) _decodeSingle(item),
      ];
    }

    throw ArgumentError.value(
      input,
      'input',
      'Expected List<E> or String, got ${input.runtimeType}',
    );
  }

  /// Unwraps a single nested list (e.g. `[["a","b"]]` from JSON) to `["a","b"]`.
  List<Object?> _flattenList(List input) {
    if (input.length == 1 && input.first is List) {
      return List<Object?>.from(input.first as List);
    }
    return List<Object?>.from(input);
  }
}
