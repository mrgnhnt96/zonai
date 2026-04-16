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

  rd.Table<T> get table => rd.Table.getFor(schema);

  static rd.Raindrop? __db;
  static rd.Raindrop get _db => __db ??= rd.Raindrop(FalseDelegate());

  @nonVirtual
  late rd.Raindrop db = _db;

  rd.InsertWithValuesBuilder<T, void> insert(T entity) {
    return db.insert(into: schema).values([entity]);
  }

  rd.InsertWithValuesBuilder<T, void> insertMany(List<T> entities) {
    return db.insert(into: schema).values(entities);
  }

  rd.UpdateWhereBuilder<T, T, void> update(
    List<Updateable<dynamic>> updates, {
    required Filter where,
  }) {
    final set = db.update(schema).set;

    return Function.apply(set, updates.take(19).toList()).where(where);
  }

  /// [selectFrom] with optional filter and pagination applied first.
  rd.SelectFromBuilder<T, T> search({
    Filter? where,
    int? limit,
    int? offset,
    Selectable<dynamic>? groupBy,
  }) {
    var builder = db.select().from(schema);

    if (where != null) {
      builder = builder.where(where);
    }

    if (limit != null) {
      builder = builder.limit(limit);
    }

    if (offset != null) {
      builder = builder.offset(offset);
    }

    if (groupBy != null) {
      builder = builder.groupBy(groupBy);
    }

    return builder;
  }

  rd.DeleteWhereBuilder<T, void> delete(Filter where, {int? limit}) {
    final builder = db.delete(from: schema).where(where);

    if (limit != null) {
      builder.limit(limit);
    }

    return builder;
  }

  rd.ToQuery<T, T> custom(
    String operation, {
    Filter? where,
    Map<String, dynamic>? values,
  }) {
    throw UnimplementedError(
      'Custom operation has not been implemented: $operation',
    );
  }
}

mixin InsertReturning<T extends Schema<T>> on CollectionOperations<T> {
  rd.InsertWithValuesBuilder<T, T> insert(T entity) {
    return db.insert(into: schema).values([entity]).returning();
  }
}

mixin UpdateReturning<T extends Schema<T>> on CollectionOperations<T> {
  rd.UpdateWhereBuilder<T, T, T> update(
    List<Updateable<dynamic>> updates, {
    required Filter where,
  }) {
    return Function.apply(
      db.update(schema).set,
      updates.take(19).toList(),
    ).where(where).returning();
  }
}

mixin DeleteReturning<T extends Schema<T>> on CollectionOperations<T> {
  rd.DeleteWhereBuilder<T, T> delete(Filter where, {int? limit}) {
    final builder = db.delete(from: schema).where(where);

    if (limit != null) {
      builder.limit(limit);
    }

    return builder.returning();
  }
}
