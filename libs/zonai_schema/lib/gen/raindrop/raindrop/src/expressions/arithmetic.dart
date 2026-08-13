// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// The arithmetic operators, spelled the same by every SQL dialect.
enum ArithmeticOperator {
  /// `a + b`
  add('+'),

  /// `a - b`
  subtract('-'),

  /// `a * b`
  multiply('*'),

  /// `a / b`
  divide('/'),

  /// `a % b`
  modulo('%');

  const ArithmeticOperator(this.sql);

  /// The SQL symbol.
  final String sql;
}

/// {@template arithmetic}
/// Arithmetic between two operands, each a literal, a column or another
/// expression.
/// {@endtemplate}
class Arithmetic<V extends num?> extends Expression<V> {
  /// {@macro arithmetic}
  const Arithmetic(this.left, this.operator, this.right);

  /// The left operand.
  final Object? left;

  /// The operator.
  final ArithmeticOperator operator;

  /// The right operand.
  final Object? right;

  @override
  SQL build() => SQL([
        const RawSQL('('),
        left,
        RawSQL(operator.sql),
        right,
        const RawSQL(')'),
      ]);
}

/// Arithmetic on a numeric column: `t.count + 1`, `t.a * t.b`.
extension ArithmeticOperators<V extends num?> on ColumnOf<V> {
  /// `this + value`
  Arithmetic<V> operator +(ColumnOr<V> value) =>
      Arithmetic<V>(this, ArithmeticOperator.add, operand(value));

  /// `this - value`
  Arithmetic<V> operator -(ColumnOr<V> value) =>
      Arithmetic<V>(this, ArithmeticOperator.subtract, operand(value));

  /// `this * value`
  Arithmetic<V> operator *(ColumnOr<V> value) =>
      Arithmetic<V>(this, ArithmeticOperator.multiply, operand(value));

  /// `this / value`
  Arithmetic<V> operator /(ColumnOr<V> value) =>
      Arithmetic<V>(this, ArithmeticOperator.divide, operand(value));
}

/// Modulo on an integer column: `t.id % 2`.
extension ModuloOperator<V extends int?> on ColumnOf<V> {
  /// `this % value`
  Arithmetic<V> operator %(ColumnOr<V> value) =>
      Arithmetic<V>(this, ArithmeticOperator.modulo, operand(value));
}
