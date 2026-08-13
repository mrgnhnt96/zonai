// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

// Raw `Updateable`s are intentional: results hold updateable columns of
// diverse value types.
// ignore_for_file: strict_raw_type

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Interface for making a class updateable.
///
/// Used internally.
abstract interface class Updateable<V> {}

/// {@template updateable_column}
/// A column that can be updated.
/// {@endtemplate}
class UpdateableColumn<V> implements Updateable<V> {
  /// {@macro updateable_column}
  const UpdateableColumn(this.column, this.value);

  /// The column in question.
  final Column<dynamic, V> column;

  /// The prepared operand: an encoded literal, a column reference, or an
  /// expression.
  final Object? value;
}

/// {@template updateable_table}
/// A table that can be updated.
/// {@endtemplate}
class UpdateableTable<S extends Schema<R>, R> implements Updateable<R> {
  /// {@macro updateable_table}
  const UpdateableTable(this.table, this.value);

  /// The table in question.
  final TableMeta<S, R> table;

  /// The row to update it with.
  final R value;
}

/// Provide a set method to a column to update a column.
extension UpdateColumn<V> on ColumnOf<V> {
  /// Set the column to [value]: a literal, another column, or an expression.
  UpdateableColumn<V> to(ColumnOr<V> value) =>
      UpdateableColumn(this!, operand(value));
}

/// {@template updateable_result}
/// List of updateable results
///
/// Used internally.
/// {@endtemplate}
class UpdateableResult<V> implements Updateable<V> {
  /// {@macro updateable_result}
  const UpdateableResult(this.updating);

  /// The updated items.
  final List<Updateable> updating;
}
