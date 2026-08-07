// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

part of 'delegates.dart';

/// {@template delegate}
/// Abstract delegate class that provides all the necessary components to talk
/// to a [SqlDialect].
/// {@endtemplate}
abstract class Delegate {
  /// {@macro delegate}
  const Delegate(this.dialect);

  /// The dialect used by the delegate.
  final SqlDialect dialect;

  /// Execute a [query] with it's [values] inside the database to which this
  /// [Delegate] is connected.
  Future<DatabaseResult> execute(String query, List<Object?> values);

  /// Perform a transaction on the database.
  Future<T> transaction<T>(
    Future<T> Function(TransactionDelegate delegate) transaction,
  );

  /// Create an insert builder for an entity.
  InsertValuesBuilder<Schema<R>, R, void> insert<R>(
    RaindropExecutor executor,
    TableMeta<dynamic, R> into,
  ) {
    return InsertValuesBuilder(
      executor,
      config: QueryConfig.from({#into: into}),
    );
  }

  /// Create a select builder for an entity.
  SelectBuilder<V> select<V>(
    RaindropExecutor executor,
    Selectable<V>? selecting,
  ) {
    return SelectBuilder(
      executor,
      config: QueryConfig.from({#selecting: selecting}),
    );
  }

  /// Create an update builder for an entity.
  UpdateSettingBuilder<Schema<R>, R, void> update<R>(
    RaindropExecutor executor,
    TableMeta<dynamic, R> table,
  ) {
    return UpdateSettingBuilder(
      executor,
      config: QueryConfig.from({#table: table}),
    );
  }

  /// Create a delete builder for an entity.
  DeleteAllBuilder<Schema<R>, R, void> delete<R>(
    RaindropExecutor executor,
    TableMeta<dynamic, R> from,
  ) {
    return DeleteAllBuilder(
      executor,
      config: QueryConfig.from({#from: from}),
    );
  }

  Stream<DatabaseResult> streamQuery(String query, List<Object?> values) {
    return streamQuery(query, values);
  }
}
