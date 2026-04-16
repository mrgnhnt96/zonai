import 'package:meta/meta.dart';
import 'package:raindrop/raindrop.dart' as rd;
import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

import 'false_delegate.dart';

part 'query_translator.dart';

/// Thin helpers around [rd.Raindrop] builders for a single [schema].
///
/// Each method returns a Raindrop builder. Builders are awaitable (they
/// implement [Future] via `ToQuery`), or you can chain more clauses and then
/// await. For row counts on update/delete, use [rd.Raindrop.execute] with
/// [rd.QueryBuilder.toQuery]; for `RETURNING`, use the SQLite extensions from
/// `package:raindrop_sqlite/raindrop_sqlite.dart` before awaiting.
abstract class CollectionOperations<T extends rd.Schema<T>> {
  CollectionOperations(this.schema);

  final T schema;

  static rd.Raindrop? __db;
  static rd.Raindrop get _db => __db ??= rd.Raindrop(FalseDelegate());

  @nonVirtual
  late rd.Raindrop db = _db;

  rd.InsertBuilder<T, void> insert(T entity) {
    return db.insert(into: schema).values([entity]);
  }

  rd.InsertBuilder<T, void> insertMany(List<T> entities) {
    return db.insert(into: schema).values(entities);
  }

  rd.UpdateBuilder<T, void> update(
    List<Updateable<T>> updates, {
    Filter? recordFilter,
  }) {
    final set = db.update(schema).set;

    var builder = Function.apply(set, updates.take(19).toList()) as dynamic;

    if (recordFilter != null) {
      builder.where(recordFilter);
    }

    return builder;
  }

  /// [selectFrom] with optional filter and pagination applied first.
  rd.SelectFromBuilder<T, T> search({
    Filter? where,
    int? limit,
    int? offset,
    Filter? recordFilter,
  }) {
    var builder = db.select().from(schema);
    final filter = switch ((where, recordFilter)) {
      (null, null) => null,
      (final f, null) => f,
      (null, final r) => r,
      (final f?, final r?) => f & r,
    };

    if (filter != null) {
      builder = builder.where(filter);
    }

    if (limit != null) {
      builder = builder.limit(limit);
    }

    if (offset != null) {
      builder = builder.offset(offset);
    }

    return builder;
  }

  rd.DeleteBuilder<T, void> delete(Filter where, {Filter? recordFilter}) {
    return db.delete(from: schema).where(where & recordFilter);
  }
}

mixin InsertReturning<T extends Schema<T>> on CollectionOperations<T> {
  rd.InsertBuilder<T, T> insert(T entity) {
    return db.insert(into: schema).values([entity]).returning();
  }
}

mixin UpdateReturning<T extends Schema<T>> on CollectionOperations<T> {
  rd.UpdateBuilder<T, T> update(
    List<Updateable<T>> updates, {
    Filter? recordFilter,
  }) {
    final set = db.update(schema).set;

    final builder = Function.apply(set, updates.take(19).toList());

    if (recordFilter != null) {
      builder.where(recordFilter);
    }

    return builder.returning();
  }
}

mixin DeleteReturning<T extends Schema<T>> on CollectionOperations<T> {
  rd.DeleteBuilder<T, T> delete(Filter where, {Filter? recordFilter}) {
    return db.delete(from: schema).where(where & recordFilter).returning();
  }
}
