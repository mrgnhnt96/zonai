// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Reads a typed column value from a row.
///
/// Pass a column-type reference (e.g. `users.id`) and receive its decoded
/// value. Returns `null` if the underlying column was null in the row.
typedef RowReader = V Function<V extends Object?>(ColumnType<V>? column);

/// {@template schema}
/// Describes the schema (table reference) for a row of type [R].
///
/// ```dart
/// class UserSchema extends Schema<User> implements User {
///   UserSchema(super.$)
///       : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
///         name = $.text('name', (s) => s.name);
///
///   @override
///   User fromRow(RowReader read) => User(
///         id: read(id),
///         name: read(name),
///       );
///
///   @override
///   final ColumnType<int?> id;
///
///   @override
///   final ColumnType<String> name;
/// }
/// ```
/// {@endtemplate}
abstract class Schema<R> implements Selectable<R> {
  /// Every concrete schema must accept a [SchemaBuilder] for [R] and use it
  /// to register columns in its initializer list.
  const Schema(SchemaBuilder<R> $);

  /// Construct a row instance from a typed [read] function.
  R fromRow(RowReader read);

  @override
  String toString() => '$runtimeType';
}

/// Convenience accessors on a schema reference.
extension SchemaX<S extends Schema<R>, R> on S {
  /// The [TableMeta] backing this schema reference.
  TableMeta<S, R> get $ => TableMeta.get(this)! as TableMeta<S, R>;

  /// Create an alias of this schema reference.
  S as(String alias) => $.aliased(alias).schema;
}

/// {@template schema_builder}
/// Carries the [TableMeta] reference for a schema under construction. Column
/// builder extensions (`$.integer`, `$.text`, etc.) register columns on
/// this builder's table.
/// {@endtemplate}
class SchemaBuilder<R> {
  /// Construct a builder for a specific [table]. Intended only for use by
  /// [TableMeta] internally; users receive an instance via the schema's
  /// constructor parameter.
  const SchemaBuilder(this.table);

  /// The table being built.
  final TableMeta<dynamic, R> table;
}
